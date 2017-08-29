# Perhaps should be called endpoint
defmodule Ace.HTTP2.Connection do
  @moduledoc false

  require Logger
  alias Ace.{
    HPack
  }
  alias Ace.HTTP2.{
    Frame,
    Stream
  }

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  def preface() do
    @preface
  end

  defstruct [
    # next: :preface, :handshake, :any, :continuation,
    next: :any,
    peer: :server,
    local_settings: nil,
    queued_settings: [],
    remote_settings: nil,
    socket: nil,
    decode_context: nil,
    encode_context: nil,
    outbound_window: nil,
    streams: nil,
    stream_supervisor: nil,
    max_peer_stream_id: 0,
    next_local_stream_id: nil,
    name: nil
    # accept_push always false for server but usable in client.
  ]

  def init({:client, {host, port}, local_settings}) do
    {:ok, connection} = :ssl.connect(host, port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)
    {:ok, default_client_settings} = Ace.HTTP2.Settings.for_client()
    initial_settings_frame = Ace.HTTP2.Settings.update_frame(local_settings, default_client_settings)

    {:ok, default_server_settings} = Ace.HTTP2.Settings.for_server()

    decode_context = HPack.new_context(4_096)
    encode_context = HPack.new_context(4_096)
    initial_state = %__MODULE__{
      socket: connection,
      outbound_window: 65_535,
      local_settings: default_client_settings,
      queued_settings: [local_settings],
      remote_settings: default_server_settings,
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      stream_supervisor: :client,
      next_local_stream_id: 1,
      name: "CLIENT (#{host}:#{port})"
    }
    state = %{initial_state | next: :handshake}

    :ssl.send(connection, Ace.HTTP2.Connection.preface())
    do_send_frames([initial_settings_frame], state)

    :ssl.setopts(connection, [active: :once])
    {:ok, {"", state}}
  end
  def init({listen_socket, {mod, config}, settings}) do
    {:ok, stream_supervisor} = Supervisor.start_link(
      [Supervisor.Spec.worker(Ace.HTTP2.Worker, [{mod, config}], restart: :transient)],
      strategy: :simple_one_for_one
    )
    {:ok, {:listening, listen_socket, stream_supervisor, settings}, 0}
  end
  def handle_info(:timeout, {:listening, listen_socket, stream_supervisor, local_settings}) do
    {:ok, socket} = :ssl.transport_accept(listen_socket)
    :ok = :ssl.ssl_accept(socket)
    {:ok, "h2"} = :ssl.negotiated_protocol(socket)

    {:ok, default_server_settings} = Ace.HTTP2.Settings.for_server()
    initial_settings_frame = Ace.HTTP2.Settings.update_frame(local_settings, default_server_settings)

    {:ok, default_client_settings} = Ace.HTTP2.Settings.for_client()

    # TODO max table size
    decode_context = HPack.new_context(4_096)
    encode_context = HPack.new_context(4_096)

    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    initial_state = %__MODULE__{
      socket: socket,
      outbound_window: 65_535,
      local_settings: default_server_settings,
      queued_settings: [local_settings],
      remote_settings: default_client_settings,
      # DEBT set when handshaking settings
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      stream_supervisor: stream_supervisor,
      next_local_stream_id: 2,
      name: "SERVER (port: #{port})"
    }

    state = %{initial_state | next: :handshake}
    do_send_frames([initial_settings_frame], state)

    :ssl.setopts(socket, [active: :once])

    {:noreply, {:pending, initial_state}}
  end
  def handle_info({:ssl, connection, @preface <> data}, {:pending, state}) do
    state = %{state | next: :handshake}
    handle_info({:ssl, connection, data}, {"", state})
  end
  def handle_info({:ssl, _, data}, {buffer, state = %__MODULE__{}}) do
    buffer = buffer <> data
    case consume(buffer, state) do
      {:ok, state} ->
        {:noreply, state}
      {:error, {error, debug}} ->
        Logger.warn("ERROR: #{inspect(error)}, #{inspect(debug)}")
        frame = Frame.GoAway.new(4, error, debug)
        outbound = Frame.GoAway.serialize(frame)
        :ok = :ssl.send(state.socket, outbound)
        Process.sleep(1_000)
        # Despite being an error the connection has successfully dealt with the client and does not need to crash
        {:stop, :normal, state}
    end
  end
  def handle_info({:ssl_closed, _socket}, {buffer, state}) do
    # TODO shut down each stream
    :ok = Supervisor.stop(state.stream_supervisor, :shutdown)
    {:stop, :normal, state}
  end
  def handle_info({:DOWN, ref, :process, _pid, reason}, {buffer, state}) do
    {_id, stream} = Enum.find(state.streams, fn
      ({_id, %{monitor: ^ref}}) ->
        true
      (_) -> false
    end)
    Logger.warn("Stopping stream #{stream.id} due to #{inspect(reason)}")
    {:ok, new_stream} = Stream.send_reset(stream, :internal_error)
    state = put_stream(state, new_stream)
    {frames, state} = send_available(state)
    :ok = do_send_frames(frames, state)
    {:noreply, {buffer, state}}
  end
  def handle_call({:new_stream, receiver}, _from, {buffer, state}) do
    {stream_id, state} = next_stream_id(state)
    stream = Stream.idle(stream_id, receiver, state.remote_settings.initial_window_size)
    state = put_stream(state, stream)
    {:reply, {:ok, {:stream, self(), stream.id, stream.monitor}}, {buffer, state}}
  end

  def handle_call({:send_request, {:stream, _, stream_id, _}, request}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    {:ok, new_stream} = Stream.send_request(stream, request)
    state = put_stream(state, new_stream)
    {frames, state} = send_available(state)
    :ok = do_send_frames(frames, state)
    {:reply, :ok, {buffer, state}}
  end

  def handle_call({:send_response, {:stream, _, stream_id, _}, response}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    {:ok, new_stream} = Stream.send_response(stream, response)
    state = put_stream(state, new_stream)
    {frames, state} = send_available(state)
    :ok = do_send_frames(frames, state)
    {:reply, :ok, {buffer, state}}
  end

  def handle_call({:send_promise, {:stream, _, original_id, _ref}, request}, from, {buffer, state}) do
    GenServer.reply(from, :ok)
    if state.remote_settings.enable_push do
      {promised_stream, state} = next_stream(state)
      headers = Ace.HTTP2.request_to_headers(request)
      {:ok, {header_block, new_encode_context}} = HPack.encode(headers, state.encode_context)
      state = %{state | encode_context: new_encode_context}

      max_frame_size = state.remote_settings.max_frame_size

      {initial_fragment, tail_block} = case header_block do
        <<to_send::binary-size(max_frame_size), remaining_data::binary>> ->
          {to_send, remaining_data}
        to_send ->
          {to_send, ""}
      end

      frames = case tail_block do
        "" ->
          [Frame.PushPromise.new(original_id, promised_stream.id, initial_fragment, true)]
        tail_block ->
          [Frame.PushPromise.new(original_id, promised_stream.id, initial_fragment, false) | pack_continuation(tail_block, original_id, max_frame_size)]
      end

      :ok = do_send_frames(frames, state)
      # SEND PROMISE
      # Then handle response

      {:ok, {[], state}} = case Stream.receive_headers(promised_stream, request) do
        {:ok, stream} ->
          state = put_stream(state, stream)
          {:ok, {[], state}}
        {:error, reason} ->
          {:error, reason}
      end
      {:noreply, {buffer, state}}
    else
      {:noreply, {buffer, state}}
    end
  end

  def handle_call({:send_data, {:stream, _, stream_id, _}, %{data: data, end_stream: end_stream}}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    {:ok, new_stream} = Stream.send_data(stream, data, end_stream)
    state = put_stream(state, new_stream)
    {frames, state} = send_available(state)
    :ok = do_send_frames(frames, state)
    {:reply, :ok, {buffer, state}}
  end

  def handle_call({:send_trailers, {:stream, _, stream_id, _}, trailers}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    {:ok, new_stream} = Stream.send_trailers(stream, trailers)
    state = put_stream(state, new_stream)
    {frames, state} = send_available(state)
    :ok = do_send_frames(frames, state)
    {:reply, :ok, {buffer, state}}
  end

  def handle_call({:send_reset, {:stream, _, stream_id, _}, error}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    {:ok, new_stream} = Stream.send_reset(stream, error)
    state = put_stream(state, new_stream)
    {frames, state} = send_available(state)
    :ok = do_send_frames(frames, state)
    {:reply, :ok, {buffer, state}}
  end

  def send_available(connection) do
    Enum.reduce(connection.streams, {[], connection}, fn
      ({_id, stream}, {out_tray, connection}) ->
        {frames, connection} = pop_stream(stream, connection)
        {out_tray ++ frames, connection}
    end)
  end
  def do_send_frames(frames, state) do
    Enum.each(frames, &Logger.debug("#{state.name} sent: #{inspect(&1)}"))
    io_list = Enum.map(frames, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, io_list)
  end
  def pop_stream(stream, connection, previous \\ [])
  def pop_stream(stream = %{queue: []}, connection, previous) do
    connection = put_stream(connection, stream)
    {previous, connection}
  end
  def pop_stream(stream = %{queue: [%{headers: headers, end_stream: end_stream} | rest]}, connection, previous) do
    stream = %{stream | queue: rest}
    {:ok, {header_block, new_encode_context}} = HPack.encode(headers, connection.encode_context)
    connection = %{connection | encode_context: new_encode_context}

    max_frame_size = connection.remote_settings.max_frame_size

    {initial_fragment, tail_block} = case header_block do
      <<to_send::binary-size(max_frame_size), remaining_data::binary>> ->
        {to_send, remaining_data}
      to_send ->
        {to_send, ""}
    end

    frames = case tail_block do
      "" ->
        [Frame.Headers.new(stream.id, initial_fragment, true, end_stream)]
      tail_block ->
        [Frame.Headers.new(stream.id, initial_fragment, false, end_stream) | pack_continuation(tail_block, stream.id, max_frame_size)]
    end
    pop_stream(stream, connection, previous ++ frames)
  end
  def pack_continuation(block, stream_id, max_frame_size) when byte_size(block) <= max_frame_size do
    [Frame.Continuation.new(stream_id, block, true)]
  end
  def pack_continuation(long_block, stream_id, max_frame_size) do
    <<to_send::binary-size(max_frame_size), remaining_block::binary>> = long_block
    [Frame.Continuation.new(stream_id, to_send, false) | pack_continuation(remaining_block, stream_id, max_frame_size)]
  end
  def pop_stream(stream = %{queue: [fragment = %{data: _} | rest]}, connection, previous) do
    available_window = min(Stream.outbound_window(stream), connection.outbound_window)
    if available_window <= 0 do
      connection = put_stream(connection, stream)
      {previous, connection}
    else
      {to_send, remaining_data} = case fragment.data do
        <<to_send::binary-size(available_window), remaining_data::binary>> ->
          {to_send, remaining_data}
        to_send ->
          {to_send, ""}
      end
      end_stream = (remaining_data == "") && fragment.end_stream
      queue = case remaining_data do
        "" ->
          rest
        data ->
          [%{data: data, end_stream: fragment.end_stream} | rest]
      end
      max_frame_size = connection.remote_settings.max_frame_size
      frames = pack_data(to_send, stream.id, end_stream, max_frame_size)
      window_used = :erlang.iolist_size(to_send)
      stream = %{stream | sent: stream.sent + window_used, queue: queue}
      connection = %{connection | outbound_window: connection.outbound_window - window_used}
      pop_stream(stream, connection, previous ++ frames)
    end
  end
  def pack_data(block, stream_id, end_stream, max_frame_size) when byte_size(block) <= max_frame_size  do
    [Frame.Data.new(stream_id, block, end_stream)]
  end
  def pack_data(long_block, stream_id, end_stream, max_frame_size) do
    <<next_block::binary-size(max_frame_size), remaining_block::binary>> = long_block
    [Frame.Data.new(stream_id, next_block, false) | pack_data(remaining_block, stream_id, end_stream, max_frame_size)]
  end
  def pop_stream(stream = %{queue: [{:reset, reason}]}, connection, previous) do
    reset_frame = Frame.RstStream.new(stream.id, reason)
    connection = put_stream(connection, %{stream | queue: []})
    {previous ++ [reset_frame], connection}
  end

  def next_stream(state) do
    {:ok, worker} = Supervisor.start_child(state.stream_supervisor, [])
    {stream_id, state} = next_stream_id(state)
    stream = Stream.reserve(stream_id, worker, state.remote_settings.initial_window_size)
    state = put_stream(state, stream)
    {stream, state}
  end
  # Do not separate frame and binary level as this step needs to know state for max_frame
  def consume(buffer, state) do
    max_frame_size = state.local_settings.max_frame_size
    case Frame.parse_from_buffer(buffer, max_length: max_frame_size) do
      {:ok, {raw_frame, unprocessed}} ->
        # Need raw frame step because parse needs to return remaining buffer for unknown frame type
        if raw_frame do
          case Frame.decode(raw_frame) do
            {:ok, frame} ->
              Logger.debug("#{state.name} received: #{inspect(frame)}")
              case consume_frame(frame, state) do
                {:ok, {frames, state}} ->
                  :ok = do_send_frames(frames, state)
                  consume(unprocessed, state)
                {:error, reason} ->
                  {:error, reason}
              end
            {:error, {:unknown_frame_type, type}} ->
              case state.next do
                :any ->
                  Logger.debug("Dropping unknown frame type (#{type})")
                  consume(unprocessed, state)
                {:continuation, _stream_id, _header_block_fragment, _end_stream} ->
                  {:error, {:protocol_error, "Unknown frame interupted continuation"}}
              end
            {:error, reason} ->
              {:error, reason}
          end
        else
          :ssl.setopts(state.socket, [active: :once])
          {:ok, {unprocessed, state}}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def consume_frame(frame = %Frame.Settings{ack: false}, state = %{next: :handshake}) do
    new_settings = Ace.HTTP2.Settings.apply_frame(frame, state.remote_settings)
    state = update_streams_initial_window_size(state, frame.initial_window_size)
    {:ok, {[Frame.Settings.ack()], %{state | remote_settings: new_settings, next: :any}}}
  end
  def consume_frame(_, %{settings: nil, next: :handshake}) do
    {:error, {:protocol_error, "Did not receive settings frame"}}
  end
  def consume_frame(frame = %Frame.Ping{ack: false}, state = %{next: :any}) do
    {:ok, {[Frame.Ping.ack(frame)], state}}
  end
  def consume_frame(%Frame.Ping{ack: true}, state = %{next: :any}) do
    {:ok, {[], state}}
  end
  def consume_frame(%Frame.GoAway{error: :no_error}, _state = %{next: :any}) do
    {:error, {:no_error, "Client closed connection"}}
  end
  def consume_frame(frame = %Frame.WindowUpdate{stream_id: 0}, state = %{next: :any}) do
    new_window = state.outbound_window + frame.increment
    # 2^31 - 1
    if new_window <= 2_147_483_647 do
      new_state = %{state | outbound_window: new_window}
      {frames, newer_state} = send_available(new_state)
      {:ok, {frames, newer_state}}
    else
      {:error, {:flow_control_error, "Total window size exceeded max allowed"}}
    end
  end
  def consume_frame(frame = %Frame.WindowUpdate{}, state = %{next: :any}) do
    {:ok, stream} = Map.fetch(state.streams, frame.stream_id)
    case Stream.receive_window_update(stream, frame.increment) do
      {:ok, new_stream} ->
        new_state = put_stream(state, new_stream)
        {frames, newer_state} = send_available(new_state)
        {:ok, {frames, newer_state}}
      {:error, {:flow_control_error, _debug}} ->
        {:ok, new_stream} = Stream.send_reset(stream, :flow_control_error)
        new_state = put_stream(state, new_stream)
        {:ok, {[Frame.RstStream.new(new_stream.id, :flow_control_error)], new_state}}
      # {:error, reason} ->
      #   {:error, reason}
    end
  end
  def consume_frame(%Frame.Priority{}, state = %{next: :any}) do
    Logger.debug("#{state.name} ignoring priority information")
    {:ok, {[], state}}
  end
  def consume_frame(frame = %Frame.Settings{}, state = %{next: :any}) do
    if frame.ack do
      [new_settings | still_queued] = state.queued_settings
      state = %{state | local_settings: new_settings, queued_settings: still_queued}
      {:ok, {[], state}}
    else
      new_settings = Ace.HTTP2.Settings.apply_frame(frame, state.remote_settings)
      state = update_streams_initial_window_size(state, frame.initial_window_size)
      {:ok, {[Frame.Settings.ack()], %{state | remote_settings: new_settings}}}
    end
  end
  def consume_frame(frame = %Frame.PushPromise{}, state = %{next: :any}) do
    # Is a server?
    # DEBT better decider here
    if rem(state.next_local_stream_id, 2) == 0 do
      {:error, {:protocol_error, "Clients cannot send push promises"}}
    else
      if frame.end_headers do
        case HPack.decode(frame.header_block_fragment, state.decode_context) do
          {:ok, {headers, new_decode_context}} ->
            state = %{state | decode_context: new_decode_context}

            {:ok, original_stream} = Map.fetch(state.streams, frame.stream_id)

            promised_stream = Stream.reserved(frame.promised_stream_id, original_stream.worker, state.remote_settings.initial_window_size)
            state = put_stream(state, promised_stream)

            {:ok, request} = Ace.HTTP2.headers_to_request(headers, true)

            {:ok, latest_original} = Stream.receive_promise(original_stream, promised_stream, request)

            state = put_stream(state, latest_original)
            {:ok, {[], state}}
        end
      else
        {:error, :todo_join_push_headers}
      end
    end
  end

  def consume_frame(frame = %Frame.RstStream{}, state = %{next: :any}) do
    {:ok, stream} = fetch_stream(state, frame)
    {:ok, new_stream} = Stream.receive_reset(stream, frame.error)
    state = put_stream(state, new_stream)
    {:ok, {[], state}}
  end
  def consume_frame(frame = %Frame.Headers{}, state = %{next: :any}) do
    case fetch_stream(state, frame) do
      {:error, :no_stream} ->
        case open_stream(state, frame.stream_id) do
          {:ok, state} ->
            consume_frame(frame, state)
          {:error, reason} ->
            {:error, reason}
        end
      {:ok, stream} ->
        if frame.end_headers do
          case HPack.decode(frame.header_block_fragment, state.decode_context) do
            {:ok, {headers, new_decode_context}} ->
              state = %{state | decode_context: new_decode_context}
              {:ok, stream} = fetch_stream(state, frame)

              case Stream.receive_headers(stream, headers, frame.end_stream) do
                {:ok, stream} ->
                  state = put_stream(state, stream)
                  {:ok, {[], %{state | max_peer_stream_id: max(stream.id, state.max_peer_stream_id)}}}
                {:error, reason} ->
                  {:error, reason}
              end
            {:error, :compression_error} ->
              {:error, {:compression_error, "bad decode"}}
          end
        else
          {:ok, {[], %{state | next: {:continuation, frame}}}}
        end
    end

  end
  def consume_frame(%Frame.Continuation{stream_id: 0}, _state) do
    {:error, {:protocol_error, "Continuation not to be sent on zero stream"}}
  end
  def consume_frame(continuation = %Frame.Continuation{}, state = %{next: {:continuation, headers_frame = %Frame.Headers{}}}) do
    header_block_fragment = headers_frame.header_block_fragment <> continuation.header_block_fragment
    if headers_frame.stream_id == continuation.stream_id do
      headers_frame = %{headers_frame | header_block_fragment: header_block_fragment}
      if continuation.end_headers do
        headers_frame = %{headers_frame | end_headers: true}
        state = %{state | next: :any}
        consume_frame(headers_frame, state)
      else
        {:ok, {[], %{state | next: {:continuation, headers_frame}}}}
      end
    else
      {:error, {:protocol_error, "Continuation had incorrect stream_id"}}
    end
  end
  def consume_frame(frame = %Frame.Data{}, state = %{next: :any}) do
    # https://tools.ietf.org/html/rfc7540#section-5.2.2

    # Deployments that do not require this capability can advertise a flow-
    # control window of the maximum size (2^31-1) and can maintain this
    # window by sending a WINDOW_UPDATE frame when any data is received.
    # This effectively disables flow control for that receiver.
    {:ok, stream} = fetch_stream(state, frame)
    case Stream.receive_data(stream, frame.data, frame.end_stream) do
      {:ok, stream} ->
        state = put_stream(state, stream)
        outbound = [Frame.WindowUpdate.new(0, 65_535), Frame.WindowUpdate.new(frame.stream_id, 65_535)]
        {:ok, {outbound, state}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(frame, %{next: next}) do
    Logger.warn("expected next '#{inspect(next)}' got: #{inspect(frame)}")
    {:error, {:protocol_error, "Unexpected frame"}}
  end

  defp update_streams_initial_window_size(state, nil) do
    state
  end
  defp update_streams_initial_window_size(state, initial_window_size) do
    streams = Enum.map(state.streams, fn({k, v}) -> {k, %{v | initial_window_size: initial_window_size}} end) |> Enum.into(%{})
    %{state| streams: streams}
  end

  def fetch_stream(state, frame) do
    case Map.fetch(state.streams, frame.stream_id) do
      {:ok, stream} ->
        {:ok, stream}
      :error ->
        {:error, :no_stream}
    end
  end

  def put_stream(state, stream) do
    new_streams = Map.put(state.streams, stream.id, stream)
    %{state | streams: new_streams}
  end

  def next_stream_id(state = %{next_local_stream_id: stream_id}) do
    {stream_id, %{state | next_local_stream_id: stream_id + 2}}
  end

  @doc """
  Only clients can open a stream, servers must reserve a stream
  """
  def open_stream(_state, 0) do
    {:error, {:protocol_error, "Stream 0 reserved for connection level communication"}}
  end
  def open_stream(_state, stream_id) when rem(stream_id, 2) == 0 do
    {:error, {:protocol_error, "Clients must start odd streams"}}
  end
  def open_stream(%{max_peer_stream_id: last_id}, stream_id) when last_id > stream_id do
    {:error, {:protocol_error, "New streams must always have a higher stream id"}}
  end
  def open_stream(connection, stream_id) do
    {:ok, worker} = Supervisor.start_child(connection.stream_supervisor, [])
    stream = Stream.idle(stream_id, worker, connection.remote_settings.initial_window_size)
    {:ok, put_stream(connection, stream)}
  end

end
