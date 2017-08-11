# Perhaps should be called endpoint
defmodule Ace.HTTP2.Connection do
  require Logger
  alias Ace.{
    HPack
  }
  alias Ace.HTTP2.{
    Frame,
    Stream
  }

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @default_settings %{}

  def preface() do
    @preface
  end

  defstruct [
    # next: :preface, :handshake, :any, :continuation,
    next: :any,
    peer: :server,
    settings: nil,
    socket: nil,
    decode_context: nil,
    encode_context: nil,
    initial_window_size: nil,
    outbound_window: nil,
    streams: nil,
    stream_supervisor: nil,
    max_peer_stream_id: 0,
    next_local_stream_id: nil,
    name: nil
    # accept_push always false for server but usable in client.
  ]

  def init({:client, {host, port}}) do
    {:ok, connection} = :ssl.connect(host, port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)
    payload = [
      Ace.HTTP2.Connection.preface(),
      # TODO push promise false
      Frame.Settings.new() |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)

    :ssl.setopts(connection, [active: :once])
    decode_context = HPack.new_context(4_096)
    encode_context = HPack.new_context(4_096)
    initial_state = %__MODULE__{
      socket: connection,
      outbound_window: 65_535,
      # DEBT set when handshaking settings
      initial_window_size: 65_535,
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      stream_supervisor: :client,
      next_local_stream_id: 1,
    }
    state = %{initial_state | next: :handshake}
    {:ok, {"", state}}
  end
  def init({listen_socket, {mod, conf}}) do
    {:ok, stream_supervisor} = Supervisor.start_link(
      [Supervisor.Spec.worker(mod, [conf], restart: :transient)],
      strategy: :simple_one_for_one
    )
    init({listen_socket, stream_supervisor})
  end
  def init({listen_socket, stream_supervisor}) when is_pid(stream_supervisor) do
    {:ok, {:listen_socket, listen_socket, stream_supervisor}, 0}
  end
  def handle_info(:timeout, {:listen_socket, listen_socket, stream_supervisor}) do
    {:ok, socket} = :ssl.transport_accept(listen_socket)
    :ok = :ssl.ssl_accept(socket)
    {:ok, "h2"} = :ssl.negotiated_protocol(socket)
    :ssl.send(socket, Frame.Settings.new() |> Frame.Settings.serialize())
    :ssl.setopts(socket, [active: :once])
    decode_context = HPack.new_context(4_096)
    encode_context = HPack.new_context(4_096)
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    initial_state = %__MODULE__{
      socket: socket,
      outbound_window: 65_535,
      # DEBT set when handshaking settings
      initial_window_size: 65_535,
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      stream_supervisor: stream_supervisor,
      next_local_stream_id: 2,
      name: "SERVER #{port}"
    }
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
        frame = Frame.GoAway.new(0, error, debug)
        outbound = Frame.GoAway.serialize(frame)
        :ok = :ssl.send(state.socket, outbound)
        # Despite being an error the connection has successfully dealt with the client and does not need to crash
        {:stop, :normal, state}
    end
  end
  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :normal, state}
  end
  def handle_info({:DOWN, ref, :process, _pid, reason}, {buffer, state}) do
    {_id, stream} = Enum.find(state.streams, fn
      ({_id, %{monitor: ^ref}}) ->
        true
      (_) -> false
    end)
    {outbound, stream} = Stream.terminate(stream, reason)
    state = put_stream(state, stream)
    outbound = Enum.map(outbound, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, outbound)
    {:noreply, {buffer, state}}
  end
  def handle_call({:new_stream, receiver}, _from, {buffer, state}) do
    {stream_id, state} = next_stream_id(state)
    stream = Stream.idle(stream_id, receiver, state.initial_window_size)
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
    # state = put_stream(state, new_stream)
    # state = Enum.reduce(outbound, state, fn
    #   (%{headers: headers, end_stream: end_stream}, state) ->
    #     {:ok, {header_block, new_encode_context}} = HPack.encode(headers, state.encode_context)
    #     state = %{state | encode_context: new_encode_context}
    #     header_frame = Frame.Headers.new(stream_id, header_block, true, end_stream)
    #     :ok = :ssl.send(state.socket, Frame.serialize(header_frame))
    #     state
    #   (%{data: data, end_stream: end_stream}, state) ->
    #     data_frame = Frame.Data.new(stream_id, data, end_stream)
    #     :ok = :ssl.send(state.socket, Frame.serialize(data_frame))
    #     state
    # end)
    # {:reply, :ok, {buffer, state}}
  end

  def send_available(connection) do
    Enum.reduce(connection.streams, {[], connection}, fn
      ({_id, stream}, {out_tray, connection}) ->
        {frames, connection} = pop_stream(stream, connection)
        {out_tray ++ frames, connection}
    end)
  end
  def do_send_frames(frames, state) do
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
    # TODO respect maximum frame size
    header_frame = Frame.Headers.new(stream.id, header_block, true, end_stream)
    pop_stream(stream, connection, previous ++ [header_frame])
  end
  def pop_stream(stream = %{queue: [fragment = %{data: _} | rest]}, connection, previous) do
    available_window = min(Stream.outbound_window(stream), connection.outbound_window)
    if available_window == 0 do
      connection = put_stream(connection, stream)
      {previous, connection}
    else
      {to_send, queue} = case fragment.data do
        <<to_send::binary-size(available_window), buffer::binary>> ->
          {to_send, [%{}]}
        to_send ->
          {to_send, rest}
      end
      # we need to return the status of the buffer so we can send end headers as needed
      # remaining messages needs requing
      window_used = :erlang.iolist_size(to_send)
      stream = %{stream | sent: stream.sent + window_used, buffer: buffer}
    end
  end

  def transmit_available(state) do
    {remaining_window, data_frames, streams} = Enum.reduce(state.streams, {state.outbound_window, [], state.streams}, fn
      ({_stream_id, _stream}, {0, data_frames, streams}) ->
        {0, data_frames, streams}
      ({stream_id, stream}, {connection_window, data_frames, streams}) ->
        available_window = min(Stream.outbound_window(stream), connection_window)
        {to_send, buffer} = case stream.buffer do
          <<to_send::binary-size(available_window), buffer::binary>> ->
            {to_send, buffer}
          to_send ->
            {to_send, ""}
        end
        case to_send do
          "" ->
            {connection_window, data_frames, streams}
          _ ->
            window_used = :erlang.iolist_size(to_send)
            stream = %{stream | sent: stream.sent + window_used, buffer: buffer}
            streams = %{streams | stream_id => stream}
            end_stream = (stream.status == :closed || stream.status == :closed_local) && (buffer == "")
            data_frame = Frame.Data.new(stream_id, to_send, end_stream)
            remaining_connection_window = connection_window - window_used

            {remaining_connection_window, data_frames ++ [data_frame], streams}
        end
    end)
    state = %{state | outbound_window: remaining_window, streams: streams}
    {:ok, {data_frames, state}}
  end

  def handle_call({:send_promise, {:stream, _, original_id, _ref}, request}, from, {buffer, state}) do
    GenServer.reply(from, :ok)
    {promised_stream, state} = next_stream(state)
    headers = Ace.HTTP2.request_to_headers(request)
    {:ok, {header_block, new_encode_context}} = HPack.encode(headers, state.encode_context)
    state = %{state | encode_context: new_encode_context}
    promise_frame = Frame.PushPromise.new(original_id, promised_stream.id, header_block, true)
    :ok = :ssl.send(state.socket, Frame.serialize(promise_frame))
    {:ok, {outbound, state}} = case Stream.receive_headers(promised_stream, request) do
      {:ok, {outbound, stream}} ->
        state = put_stream(state, stream)
        {:ok, {outbound, state}}
      {:error, reason} ->
        {:error, reason}
    end
    IO.inspect(outbound)
    {:noreply, {buffer, state}}
  end
  def handle_call({:send_data, {:stream, _, stream_id, _}, %{data: data, end_stream: end_stream}}, _from, {conn_buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    if stream.status == :closed || stream.status == :closed_local do
      Logger.info("Data lost because stream already closed")
      # DEBT expose through backpressure
      {[], state}
    else
      connection_window = state.outbound_window
      stream_window = Stream.outbound_window(stream)
      available_window = min(stream_window, connection_window)
      {to_send, buffer} = case data do
        <<to_send::binary-size(available_window), buffer::binary>> ->
          {to_send, buffer}
        to_send ->
          {to_send, ""}
      end

      true = :erlang.is_binary(to_send)
      window_used = :erlang.iolist_size(to_send)
      # stream = %{stream | sent: stream.sent + window_used, buffer: buffer}
      stream = case {stream.status, end_stream} do
        {:closed_remote, true} ->
          %{stream | status: :closed}
        {:open, true} ->
          %{stream | status: :closed_local}
        {_, false} ->
          stream
      end
      streams = %{state.streams | stream_id => stream}
      data_frame = Frame.Data.new(stream_id, to_send, end_stream && (buffer == ""))
      remaining_connection_window = connection_window - window_used
      state = %{state | streams: streams, outbound_window: remaining_connection_window}
      :ok = :ssl.send(state.socket, Frame.serialize(data_frame))
      {:reply, :ok, {conn_buffer, state}}
    end
  end
  def handle_call({:send_trailers, {:stream, _, stream_id, _}, trailers}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    {:ok, {outbound, new_stream}} = Stream.send_trailers(stream, trailers)
    state = put_stream(state, new_stream)
    state = Enum.reduce(outbound, state, fn(%{headers: headers, end_stream: end_stream}, state) ->
      {:ok, {header_block, new_encode_context}} = HPack.encode(headers, state.encode_context)
      state = %{state | encode_context: new_encode_context}
      header_frame = Frame.Headers.new(stream_id, header_block, true, end_stream)
      :ok = :ssl.send(state.socket, Frame.serialize(header_frame))
      state
    end)
    {:reply, :ok, {buffer, state}}
  end
  def handle_call({:send_reset, {:stream, _, stream_id, _}, error, reason}, _from, {buffer, state}) do
    {:ok, stream} = Map.fetch(state.streams, stream_id)
    state = Stream.send_reset(stream, error, reason)
    |> handle_stream_response(state)
    |> handle_connection_response
    {:reply, :ok, {buffer, state}}
  end

  def handle_connection_response({:ok, {frames, state}}) do
    IO.inspect(frames)
    io_list = Enum.map(frames, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, io_list)
    state
  end

  def next_stream(state) do
    {:ok, worker} = Supervisor.start_child(state.stream_supervisor, [])
    {stream_id, state} = next_stream_id(state)
    stream = Stream.reserve(stream_id, worker, state.initial_window_size)
    state = put_stream(state, stream)
    {stream, state}
  end
  def consume(buffer, state) do
    case Frame.parse_from_buffer(buffer, max_length: 16_384) do
      {:ok, {raw_frame, unprocessed}} ->

        if raw_frame do
          case Frame.decode(raw_frame) do
            {:ok, frame} ->
              Logger.debug("#{state.name}: #{inspect(frame)}")
              case consume_frame(frame, state) do
                {:ok, {outbound, state}} when is_list(outbound) ->
                  IO.inspect(outbound)
                  outbound = Enum.map(outbound, &Frame.serialize/1)
                  :ok = :ssl.send(state.socket, outbound)
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

  def consume_frame(settings = %Frame.Settings{ack: false}, state = %{settings: nil, next: :handshake}) do
    case update_settings(settings, %{state | settings: @default_settings}) do
      {:ok, new_state} ->
        new_state = %{new_state | next: :any}
        # DEBT only do this if initial_window_size has increased
        {:ok, {frames, newer_state}} = transmit_available(new_state)
        # |> IO.inspect
        {:ok, {[Frame.Settings.ack() | frames], newer_state}}
      {:error, reason} ->
        {:error, reason}
    end
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
      {[], %{state | outbound_window: new_window}}
      transmit_available(%{state | outbound_window: new_window})
    else
      {:error, {:flow_control_error, "Total window size exceeded max allowed"}}
    end
  end
  def consume_frame(frame = %Frame.WindowUpdate{}, state = %{next: :any}) do
    {:ok, stream} = Map.fetch(state.streams, frame.stream_id)
    {:ok, {outbound, new_stream}} = Stream.receive_window_update(stream, frame.increment)
    new_state = put_stream(state, new_stream)
    {:ok, {outbound, new_state}}
  end
  def consume_frame(%Frame.Priority{}, state = %{next: :any}) do
    IO.inspect("Ignoring priority frame")
    {:ok, {[], state}}
  end
  def consume_frame(settings = %Frame.Settings{}, state = %{next: :any}) do
    if settings.ack do
      {:ok, {[], state}}
    else
      case update_settings(settings, state) do
        {:ok, new_state} ->
          {:ok, {[Frame.Settings.ack()], new_state}}
        {:error, reason} ->
          {:error, reason}
      end
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

            promised_stream = Stream.reserved(frame.promised_stream_id, original_stream.worker, state.initial_window_size)
            state = put_stream(state, promised_stream)

            {:ok, request} = Ace.HTTP2.build_request(headers)

            {:ok, {outbound, latest_original}} = Stream.receive_promise(original_stream, promised_stream, request)

            state = put_stream(state, latest_original)
            {:ok, {outbound, state}}
        end
      else
        {:error, :todo_join_push_headers}
      end
    end
  end

  def consume_frame(frame = %Frame.RstStream{}, state = %{next: :any}) do
    {:ok, stream} = fetch_stream(state, frame)
    Stream.receive_reset(stream, frame.error)
    |> handle_stream_response(state)
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
                {:ok, {outbound, stream}} ->
                  state = put_stream(state, stream)
                  {:ok, {outbound, %{state | max_peer_stream_id: max(stream.id, state.max_peer_stream_id)}}}
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
    # TODO check stream ids
    headers_frame = %{headers_frame | header_block_fragment: header_block_fragment}
    if continuation.end_headers do
      headers_frame = %{headers_frame | end_headers: true}
      state = %{state | next: :any}
      consume_frame(headers_frame, state)
    else
      {:ok, {[], %{state | next: {:continuation, headers_frame}}}}
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
      {:ok, {outbound, stream}} ->
        state = put_stream(state, stream)
        outbound = outbound ++ [Frame.WindowUpdate.new(0, 65_535), Frame.WindowUpdate.new(frame.stream_id, 65_535)]
        {:ok, {outbound, %{state | max_peer_stream_id: max(stream.id, state.max_peer_stream_id)}}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(frame, %{next: next}) do
    IO.inspect("expected next '#{inspect(next)}' got: #{inspect(frame)}")
    {:error, {:protocol_error, "Unexpected frame"}}
  end

  def handle_stream_response({:ok, {outbound, stream}}, previous_state) do
    state = put_stream(previous_state, stream)
    {:ok, {outbound, state}}
  end
  def handle_stream_response({:error, reason}, _previous_state) do
    {:error, reason}
  end

  # TODO handle all settings
  def update_settings(new, state) do
    new_state = state
    |> update_initial_window_size(new.initial_window_size)
    # case new.max_frame_size do
    #   nil ->
    #   x when x < 16_384 ->
    #     {:error, {:protocol_error, "max_frame_size too small"}}
    #   new ->
    #     {:ok, state}
    # end
    {:ok, new_state}
  end

  defp update_initial_window_size(state, nil) do
    state
  end
  defp update_initial_window_size(state, initial_window_size) do
    streams = Enum.map(state.streams, fn({k, v}) -> {k, %{v | initial_window_size: initial_window_size}} end) |> Enum.into(%{})
    %{state| initial_window_size: initial_window_size, streams: streams}
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
    {:error, {:protocol_error, "Stream 0 reserved for connectionlevel communication"}}
  end
  def open_stream(_state, stream_id) when rem(stream_id, 2) == 0 do
    {:error, {:protocol_error, "Clients must start odd streams"}}
  end
  def open_stream(%{max_peer_stream_id: last_id}, stream_id) when last_id > stream_id do
    {:error, {:protocol_error, "New streams must always have a higher stream id"}}
  end
  def open_stream(connection, stream_id) do
    {:ok, worker} = Supervisor.start_child(connection.stream_supervisor, [])
    stream = Stream.idle(stream_id, worker, connection.initial_window_size)
    {:ok, put_stream(connection, stream)}
  end

end
