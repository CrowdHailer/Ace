defmodule Ace.HTTP2 do
  @moduledoc """
  **Hypertext Transfer Protocol Version 2 (HTTP/2)**

  > HTTP/2 enables a more efficient use of network
  > resources and a reduced perception of latency by introducing header
  > field compression and allowing multiple concurrent exchanges on the
  > same connection.  It also introduces unsolicited push of
  > representations from servers to clients.

  *Quote from [rfc 7540](https://tools.ietf.org/html/rfc7540).*
  """

  alias Ace.HTTP2.{
    Frame,
    Request
  }

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @default_settings %{}

  def preface() do
    @preface
  end

  defstruct [
    # next: :preface, :settings, :continuation, :any
    next: :any,
    buffer: "",
    settings: nil,
    socket: nil,
    decode_context: nil,
    encode_context: nil,
    streams: nil,
    router: nil,
    config: nil,
    stream_supervisor: nil
    # accept_push always false for server but usable in client.
  ]

  use GenServer
  def start_link(listen_socket, app) do
    GenServer.start_link(__MODULE__, {listen_socket, app})
  end

  def init({listen_socket, app}) do
    {:ok, {:listen_socket, listen_socket, app}, 0}
  end
  def handle_info(:timeout, {:listen_socket, listen_socket, {router, config}}) do
    {:ok, socket} = :ssl.transport_accept(listen_socket)
    :ok = :ssl.ssl_accept(socket)
    {:ok, "h2"} = :ssl.negotiated_protocol(socket)
    :ssl.send(socket, Frame.Settings.new() |> Frame.Settings.serialize())
    :ssl.setopts(socket, [active: :once])
    {:ok, decode_context} = HPack.Table.start_link(65_536)
    {:ok, encode_context} = HPack.Table.start_link(65_536)
    {:ok, stream_supervisor} = Supervisor.start_link([], [strategy: :one_for_one])
    initial_state = %__MODULE__{
      socket: socket,
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      router: router,
      config: config,
      stream_supervisor: stream_supervisor
    }
    {:noreply, {:pending, initial_state}}
  end
  def handle_info({:ssl, connection, @preface <> data}, {:pending, state}) do
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
  def handle_info({{:stream, stream_id, _ref}, message}, state) do
    {frames, state} = stream_set_dispatch(stream_id, message, state)
    outbound = Enum.map(frames, &Frame.serialize/1)
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
              IO.inspect(frame)
              case consume_frame(frame, state) do
                {outbound, state} when is_list(outbound) ->
                  outbound = Enum.map(outbound, &Frame.serialize/1)
                  :ok = :ssl.send(state.socket, outbound)
                  consume(unprocessed, state)
                {:error, reason} ->
                  {:error, reason}
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

  def consume_frame(settings = %Frame.Settings{}, state = %{settings: nil}) do
    case update_settings(settings, %{state | settings: @default_settings}) do
      {:ok, new_state} ->
        {[Frame.Settings.ack()], new_state}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(_, %{settings: nil}) do
    {:error, {:protocol_error, "Did not receive settings frame"}}
  end
  # Consume settings ack make sure we are not in a state of settings nil
  # def consume_frame({4, <<1>>, 0, ""}, state = %{settings: %{}}) do
  #   {[], state}
  # end
  def consume_frame(frame = %Frame.Ping{}, state) do
    {[Frame.Ping.ack(frame)], state}
  end
  def consume_frame(%Frame.GoAway{error: :no_error}, _state) do
    {:error, {:no_error, "Client closed connection"}}
  end
  def consume_frame(%Frame.WindowUpdate{stream_id: 0}, state) do
    IO.inspect("total window update")
    {[], state}
  end
  def consume_frame(%Frame.WindowUpdate{stream_id: _}, state) do
    IO.inspect("Stream window update")
    {[], state}
  end
  def consume_frame(%Frame.Priority{}, state) do
    IO.inspect("Ignoring priority frame")
    {[], state}
  end
  def consume_frame(settings = %Frame.Settings{}, state) do
    case update_settings(settings, state) do
      {:ok, new_state} ->
        {[Frame.Settings.ack()], new_state}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume_frame(%Frame.PushPromise{}, _state) do
    {:error, {:protocol_error, "Clients cannot send push promises"}}
  end
  def consume_frame(%Frame.RstStream{}, state) do
    IO.inspect("Ignoring rst_stream frame")
    {[], state}
  end
  def consume_frame(frame = %Frame.Headers{}, state) do
    # TODO pass through end stream flag
    if frame.end_headers do
      headers = HPack.decode(frame.header_block_fragment, state.decode_context)
      # preface bad name as could be trailers perhaps metadata
      preface = %{headers: headers, end_stream: frame.end_stream}
      state = dispatch(frame.stream_id, preface, state)
      {[], state}
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
      state = dispatch(frame.stream_id, preface, state)
      {[], state}
    else
      {[], %{state | next: {:continuation, frame.stream_id, buffer}}}
    end
  end
  def consume_frame(frame = %Frame.Data{}, state) do
    # https://tools.ietf.org/html/rfc7540#section-5.2.2

    # Deployments that do not require this capability can advertise a flow-
    # control window of the maximum size (2^31-1) and can maintain this
    # window by sending a WINDOW_UPDATE frame when any data is received.
    # This effectively disables flow control for that receiver.
    data = %{data: frame.data, end_stream: frame.end_stream}
    state = dispatch(frame.stream_id, data, state)
    {[Frame.WindowUpdate.new(0, 65_535), Frame.WindowUpdate.new(frame.stream_id, 65_535)], state}
  end

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
    stream = case Map.get(state.streams, stream_id) do
      nil ->
        stream_spec = stream_spec(stream_id, Ace.HTTP2.StreamHandler, state)
        {:ok, pid} = Supervisor.start_child(state.stream_supervisor, stream_spec)
        ref = Process.monitor(pid)
        {ref, pid}
      {ref, pid} ->
        {ref, pid}
    end
    {ref, pid} = stream
    stream_ref = {:stream, self(), stream_id, ref}
    # Maybe send with same ref as used for reply
    send(pid, {stream_ref, message})
    streams = Map.put(state.streams, stream_id, stream)
    %{state | streams: streams}
  end

  def stream_spec(id, handler, %{config: config, router: router}) do
    Supervisor.Spec.worker(handler, [config, router], [restart: :temporary, id: id])
  end
end
