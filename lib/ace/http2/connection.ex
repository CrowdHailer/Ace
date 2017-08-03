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
    buffer: "",
    settings: nil,
    socket: nil,
    decode_context: nil,
    encode_context: nil,
    initial_window_size: nil,
    outbound_window: nil,
    streams: nil,
    stream_supervisor: nil,
    client_stream_id: 0,
    next_available_stream_id: nil,
    name: nil
    # accept_push always false for server but usable in client.
  ]

  use GenServer
  def start_link(listen_socket, stream_supervisor) do
    IO.inspect("start server")
    GenServer.start_link(__MODULE__, {listen_socket, stream_supervisor})
  end

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
      next_available_stream_id: 1,
    }
    state = %{initial_state | next: :handshake}
    {:ok, state}
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
      name: "SERVER #{port}"
    }
    {:noreply, {:pending, initial_state}}
  end
  def handle_info({:ssl, connection, @preface <> data}, {:pending, state}) do
    state = %{state | next: :handshake}
    handle_info({:ssl, connection, data}, state)
  end
  def handle_info({:ssl, _, data}, state = %__MODULE__{}) do
    data = state.buffer <> data
    state = %{state | buffer: ""}
    case consume(data, state) do
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
  def handle_info({{:stream, stream_id, _ref}, message}, state) do
    {frames, state} = stream_set_dispatch(stream_id, message, state)
    outbound = Enum.map(frames, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, outbound)
    {:noreply, state}
  end
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {_id, stream} = Enum.find(state.streams, fn
      ({_id, %{monitor: ^ref}}) ->
        true
      (_) -> false
    end)
    {outbound, stream} = Stream.terminate(stream, reason)
    streams = Map.put(state.streams, stream.id, stream)
    state = %{state | streams: streams}
    outbound = Enum.map(outbound, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, outbound)
    {:noreply, state}
  end
  # TODO this is replaced by next calls
  def handle_call({:request, headers, receiver}, _from, state) do
    stream_id = state.next_available_stream_id
    monitor = Process.monitor(receiver)
    stream = %Stream{
      id: stream_id,
      status: :idle,
      worker: receiver,
      monitor: monitor,
      initial_window_size: state.initial_window_size,
      sent: 0,
      incremented: 0,
      buffer: "",
    }
    streams = Map.put(state.streams, stream_id, stream)
    state = %{state | next_available_stream_id: stream_id + 2, streams: streams}
    {frames, state} = stream_set_dispatch(stream_id, %{headers: headers, end_stream: true}, state)
    outbound = Enum.map(frames, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, outbound)
    {:reply, {:ok, {:stream, self(), stream.id, stream.monitor}}, state}
  end
  def handle_call({:new_stream, receiver}, _from, state) do
    stream_id = state.next_available_stream_id
    monitor = Process.monitor(receiver)
    stream = %Stream{
      id: stream_id,
      status: :idle,
      worker: receiver,
      monitor: monitor,
      initial_window_size: state.initial_window_size,
      sent: 0,
      incremented: 0,
      buffer: "",
    }
    streams = Map.put(state.streams, stream_id, stream)
    state = %{state | next_available_stream_id: stream_id + 2, streams: streams}
    {:reply, {:ok, {:stream, self(), stream.id, stream.monitor}}, state}
  end
  def handle_call({:send, {:stream, _, stream_id, _}, message}, _from, state) do
    {frames, state} = stream_set_dispatch(stream_id, message, state)
    outbound = Enum.map(frames, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, outbound)
    {:reply, :ok, state}
  end

  def consume(buffer, state) do
    case Frame.parse_from_buffer(buffer, max_length: 16_384) do
      {:ok, {raw_frame, unprocessed}} ->

        if raw_frame do
          case Frame.decode(raw_frame) do
            {:ok, frame} ->
              Logger.debug("#{state.name}: #{inspect(frame)}")
              case consume_frame(frame, state) do
                {outbound, state} when is_list(outbound) ->
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
          state = %{state | buffer: unprocessed}
          :ssl.setopts(state.socket, [active: :once])
          {:ok, state}
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
        {frames, newer_state} = transmit_available(new_state)
        # |> IO.inspect
        {[Frame.Settings.ack() | frames], newer_state}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(_, %{settings: nil, next: :handshake}) do
    {:error, {:protocol_error, "Did not receive settings frame"}}
  end
  def consume_frame(frame = %Frame.Ping{ack: false}, state = %{next: :any}) do
    {[Frame.Ping.ack(frame)], state}
  end
  def consume_frame(%Frame.Ping{ack: true}, state = %{next: :any}) do
    {[], state}
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
  def consume_frame(frame = %Frame.WindowUpdate{stream_id: _}, state = %{next: :any}) do
    case dispatch(frame.stream_id, {:window_update, frame.increment}, state) do
      {:ok, {outbound, new_state}} ->
        {frames, newer_state} = transmit_available(new_state)
        {outbound ++ frames, newer_state}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(%Frame.Priority{}, state = %{next: :any}) do
    IO.inspect("Ignoring priority frame")
    {[], state}
  end
  def consume_frame(settings = %Frame.Settings{}, state = %{next: :any}) do
    if settings.ack do
      {[], state}
    else
      case update_settings(settings, state) do
        {:ok, new_state} ->
          {[Frame.Settings.ack()], new_state}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end
  def consume_frame(%Frame.PushPromise{}, _state = %{next: :any}) do
    {:error, {:protocol_error, "Clients cannot send push promises"}}
  end
  def consume_frame(frame = %Frame.RstStream{}, state = %{next: :any}) do
    case dispatch(frame.stream_id, :reset, state) do
      {:ok, {outbound, state}} ->
        {outbound, state}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(frame = %Frame.Headers{}, state = %{next: :any}) do
    if frame.end_headers do
      case HPack.decode(frame.header_block_fragment, state.decode_context) do
        {:ok, {headers, new_decode_context}} ->
          # preface bad name as could be trailers perhaps metadata
          preface = %{headers: headers, end_stream: frame.end_stream}
          state = %{state | decode_context: new_decode_context}
          case dispatch(frame.stream_id, preface, state) do
            {:ok, {outbound, state}} ->
              {outbound, state}
            {:error, reason} ->
              {:error, reason}
          end
        {:error, :compression_error} ->
          {:error, {:compression_error, "bad decode"}}
      end
    else
      {[], %{state | next: {:continuation, frame.stream_id, frame.header_block_fragment, frame.end_stream}}}
    end
  end
  def consume_frame(frame = %Frame.Continuation{}, state = %{next: {:continuation, _stream_id, buffer, end_stream}}) do
    buffer = buffer <> frame.header_block_fragment
    if frame.end_headers do
      {:ok, {headers, new_decode_context}} = HPack.decode(buffer, state.decode_context)
      # preface bad name as could be trailers perhaps metadata
      state = %{state | decode_context: new_decode_context}
      preface = %{headers: headers, end_stream: end_stream}
      case dispatch(frame.stream_id, preface, state) do
        {:ok, {outbound, state}} ->
          state = %{state | next: :any}
          {outbound, state}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {[], %{state | next: {:continuation, frame.stream_id, buffer, end_stream}}}
    end
  end
  def consume_frame(frame = %Frame.Data{}, state = %{next: :any}) do
    # https://tools.ietf.org/html/rfc7540#section-5.2.2

    # Deployments that do not require this capability can advertise a flow-
    # control window of the maximum size (2^31-1) and can maintain this
    # window by sending a WINDOW_UPDATE frame when any data is received.
    # This effectively disables flow control for that receiver.
    data = %{data: frame.data, end_stream: frame.end_stream}
    case dispatch(frame.stream_id, data, state) do
      {:ok, {outbound, state}} ->
        {outbound ++ [Frame.WindowUpdate.new(0, 65_535), Frame.WindowUpdate.new(frame.stream_id, 65_535)], state}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(frame, %{next: next}) do
    IO.inspect("expected next '#{inspect(next)}' got: #{inspect(frame)}")
    {:error, {:protocol_error, "Unexpected frame"}}
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
    {data_frames, state}
  end

  def dispatch(stream_id, message, state) do
    # NOTE only evaluate creating new stream if one does not exist
    # DEBT don't have stream rely on shape of connection state
    case fetch_stream(state, stream_id) do
      {:ok, stream} ->
        case Stream.consume(stream, message) do
          {:ok, {outbound, stream}} ->
            streams = Map.put(state.streams, stream_id, stream)
            {:ok, {outbound, %{state | streams: streams, client_stream_id: max(stream.id, state.client_stream_id)}}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def stream_set_dispatch(id, request = %Ace.Request{}, state) do
    authority = case request.authority do
      :connection ->
        "todo.com"
    end
    headers = [
      {":scheme", Atom.to_string(request.scheme)},
      {":authority", authority},
      {":method", Atom.to_string(request.method)},
      {":path", request.path} |
      request.headers
    ]
    case request.body do
      false ->
        stream_set_dispatch(id, %{headers: headers, end_stream: true}, state)
      true ->
        stream_set_dispatch(id, %{headers: headers, end_stream: false}, state)
    end
  end
  def stream_set_dispatch(id, %{headers: headers, end_stream: end_stream}, state) do
    # Map or array to map, best receive a list and response takes care of ordering
    headers = for h <- headers, do: h
    {:ok, {header_block, new_encode_context}} = HPack.encode(headers, state.encode_context)
    state = %{state | encode_context: new_encode_context}
    streams = case Map.fetch(state.streams, id) do
      {:ok, stream = %{status: :idle}} ->
        new_status = if end_stream, do: :closed_local, else: :open
        %{state.streams | id => %{stream | status: new_status}}
      _ ->
      # DEBT remove
        state.streams
    end
    state = %{state | streams: streams}
    header_frame = Frame.Headers.new(id, header_block, true, end_stream)
    {[header_frame], state}
  end
  def stream_set_dispatch(stream_id, %{data: data, end_stream: end_stream}, state) do
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
      stream = %{stream | sent: stream.sent + window_used, buffer: buffer}
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
      {[data_frame], %{state | streams: streams, outbound_window: remaining_connection_window}}
    end
  end
  def stream_set_dispatch(stream_id, %Ace.HTTP2.Stream.Reset{error: reason}, state) do
    # DEBT does not check if stream idle or already closed
    # stream = fetch_stream(state, stream_id)
    rst_frame = Frame.RstStream.new(stream_id, reason)
    {[rst_frame], state}
  end

  defp fetch_stream(state, stream_id) do
    case Map.fetch(state.streams, stream_id) do
      {:ok, stream} ->
        {:ok, stream}
      :error ->
        new_stream(stream_id, state)
    end
  end

  def new_stream(0, _) do
    {:error, {:protocol_error, "Stream 0 reserved for connection"}}
  end
  def new_stream(stream_id, state) when rem(stream_id, 2) == 1 do
    if stream_id > state.client_stream_id do
      {:ok, Stream.idle(stream_id, state)}
    else
      {:error, {:protocol_error, "New streams must always have a higher stream id"}}
    end
  end
  def new_stream(_, _) do
    {:error, {:protocol_error, "Clients must start odd streams"}}
  end
end
