defmodule Ace.HTTP2.Connection do
  @moduledoc """
  **Hypertext Transfer Protocol Version 2 (HTTP/2)**

  > HTTP/2 enables a more efficient use of network
  > resources and a reduced perception of latency by introducing header
  > field compression and allowing multiple concurrent exchanges on the
  > same connection.  It also introduces unsolicited push of
  > representations from servers to clients.

  *Quote from [rfc 7540](https://tools.ietf.org/html/rfc7540).*
  """

  require Logger
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
    streams: nil,
    stream_supervisor: nil
    # accept_push always false for server but usable in client.
  ]

  use GenServer
  def start_link(listen_socket, stream_supervisor) do
    IO.inspect("start server")
    GenServer.start_link(__MODULE__, {listen_socket, stream_supervisor})
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
    {:ok, decode_context} = HPack.Table.start_link(65_536)
    {:ok, encode_context} = HPack.Table.start_link(65_536)
    initial_state = %__MODULE__{
      socket: socket,
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      stream_supervisor: stream_supervisor
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
    streams = Map.put(state.streams, stream.stream_id, stream)
    state = %{state | streams: streams}
    outbound = Enum.map(outbound, &Frame.serialize/1)
    :ok = :ssl.send(state.socket, outbound)
    {:noreply, state}
  end

  def stream_set_dispatch(id, %{headers: headers, end_stream: end_stream}, state) do
    # Map or array to map, best receive a list and response takes care of ordering
    headers = for h <- headers, do: h
    header_block = HPack.encode(headers, state.encode_context)
    header_frame = Frame.Headers.new(id, header_block, true, end_stream)
    {[header_frame], state}
  end
  def stream_set_dispatch(id, %{data: data, end_stream: end_stream}, state) do
    data_frame = Frame.Data.new(id, data, end_stream)
    {[data_frame], state}
  end

  def consume(buffer, state) do
    case Frame.parse_from_buffer(buffer, max_length: 16_384) do
      {:ok, {raw_frame, unprocessed}} ->
        if raw_frame do
          case Frame.decode(raw_frame) do
            {:ok, frame} ->
              Logger.debug(inspect(frame))
              case consume_frame(frame, state) do
                {outbound, state} when is_list(outbound) ->
                  outbound = Enum.map(outbound, &Frame.serialize/1)
                  :ok = :ssl.send(state.socket, outbound)
                  consume(unprocessed, state)
                {:error, reason} ->
                  {:error, reason}
              end
            {:error, {:unknown_frame_type, _type}} ->
              consume(unprocessed, state)
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
        {[Frame.Settings.ack()], new_state}
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
  def consume_frame(%Frame.WindowUpdate{stream_id: 0}, state = %{next: :any}) do
    IO.inspect("total window update")
    {[], state}
  end
  def consume_frame(%Frame.WindowUpdate{stream_id: _}, state = %{next: :any}) do
    IO.inspect("Stream window update")
    {[], state}
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
      headers = HPack.decode(frame.header_block_fragment, state.decode_context)
      # preface bad name as could be trailers perhaps metadata
      preface = %{headers: headers, end_stream: frame.end_stream}
      case dispatch(frame.stream_id, preface, state) do
        {:ok, {outbound, state}} ->
          {outbound, state}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {[], %{state | next: {:continuation, frame.stream_id, frame.header_block_fragment, frame.end_stream}}}
    end
  end
  def consume_frame(frame = %Frame.Continuation{}, state = %{next: {:continuation, _stream_id, buffer, end_stream}}) do
    buffer = buffer <> frame.header_block_fragment
    if frame.end_headers do
      headers = HPack.decode(buffer, state.decode_context)
      # preface bad name as could be trailers perhaps metadata
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
    case new.max_frame_size do
      nil ->
        {:ok, state}
      x when x < 16_384 ->
        {:error, {:protocol_error, "max_frame_size too small"}}
      new ->
        IO.inspect("updating frame size (#{new})")
        {:ok, state}
    end
  end

  def dispatch(stream_id, message, state) do
    # NOTE only evaluate creating new stream if one does not exist
    # DEBT don't have stream rely on shape of connection state
    case fetch_stream(state, stream_id) do
      {:ok, stream} ->
        case Stream.consume(stream, message) do
          {:ok, {outbound, stream}} ->
            streams = Map.put(state.streams, stream_id, stream)
            {:ok, {outbound, %{state | streams: streams}}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
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
    {:ok, Stream.idle(stream_id, state)}
  end
  def new_stream(_, _) do
    {:error, {:protocol_error, "Clients must start odd streams"}}
  end
end
