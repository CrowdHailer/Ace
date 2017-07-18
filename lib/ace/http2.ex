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
  def handle_info({:ssl, _, @preface <> data}, {:pending, state}) do
    consume(data, state)
  end
  def handle_info({:ssl, _, data}, state = %__MODULE__{}) do
    data = state.buffer <> data
    state = %{state | buffer: ""}
    consume(data, state)
  end
  def handle_info({:stream, stream_id, {:headers, headers}}, state) do
    # accept list [frame/headers/data]
    IO.inspect(headers)
    headers_payload = encode_response_headers(headers, state.encode_context)
    headers_size = :erlang.iolist_size(headers_payload)
    headers_flags = <<0::5, 1::1, 0::1, 0::1>>
    header = <<headers_size::24, 1::8, headers_flags::binary, 0::1, 1::31, headers_payload::binary>>
    :ok = :ssl.send(state.socket, header)
    {:noreply, state}
  end
  def handle_info({:stream, stream_id, {:data, {data_payload, :end}}}, state) do
    frame = Frame.Data.new(stream_id, data_payload, true)
    IO.inspect(frame)
    outbound = Frame.Data.serialize(frame)
    :ok = :ssl.send(state.socket, outbound)
    {:noreply, state}
  end

  def encode_response_headers(headers, context) do
    headers = Enum.map(headers, fn
      ({:status, status}) ->
        {":status", "#{status}"}
      (header) ->
        header
    end)
    HPack.encode(headers, context)
  end

  def consume(buffer, state) do
    case Frame.parse_from_buffer(buffer, max_length: 16_384) do
      {:ok, {frame, unprocessed}} ->
        IO.inspect(frame)
        if frame do
          case Frame.decode(frame) do
            {:ok, frame} ->
              IO.inspect(frame)
              # Could consume with only settings
              case consume_frame(frame, state) do
                {outbound, state} when is_list(outbound) ->
                  outbound = Enum.map(outbound, &Frame.serialize/1)
                  :ok = :ssl.send(state.socket, outbound)
                  consume(unprocessed, state)
                {:error, error} when is_atom(error) ->
                  frame = Frame.GoAway.new(0, error)
                  outbound = Frame.GoAway.serialize(frame)
                  :ok = :ssl.send(state.socket, outbound)
                  # Despite being an error the connection has successfully dealt with the client and does not need to crash
                  {:stop, :normal, state}
                {:error, {error, debug}} ->
                  frame = Frame.GoAway.new(0, error, debug)
                  outbound = Frame.GoAway.serialize(frame)
                  :ok = :ssl.send(state.socket, outbound)
                  # Despite being an error the connection has successfully dealt with the client and does not need to crash
                  {:stop, :normal, state}
              end
            {:error, {error, debug}} ->
              frame = Frame.GoAway.new(0, error, debug)
              outbound = Frame.GoAway.serialize(frame)
              :ok = :ssl.send(state.socket, outbound)
              # Despite being an error the connection has successfully dealt with the client and does not need to crash
              {:stop, :normal, state}
          end

        else
          state = %{state | buffer: unprocessed}
          :ssl.setopts(state.socket, [active: :once])
          {:noreply, state}
        end
      {:error, {error, debug}} ->
        frame = Frame.GoAway.new(0, error, debug)
        outbound = Frame.GoAway.serialize(frame)
        :ok = :ssl.send(state.socket, outbound)
        # Despite being an error the connection has successfully dealt with the client and does not need to crash
        {:stop, :normal, state}
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
  def consume_frame(_, state = %{settings: nil}) do
    {:error, {:protocol_error, "Did not receive settings frame"}}
  end
  # Consume settings ack make sure we are not in a state of settings nil
  # def consume_frame({4, <<1>>, 0, ""}, state = %{settings: %{}}) do
  #   {[], state}
  # end
  def consume_frame(frame = %Frame.Ping{}, state) do
    {[Frame.Ping.ack(frame)], state}
  end
  def consume_frame(%Frame.WindowUpdate{stream_id: 0}, state) do
    IO.inspect("total window update")
    {[], state}
  end
  def consume_frame(%Frame.WindowUpdate{stream_id: _}, state) do
    IO.inspect("Stream window update")
    {[], state}
  end
  def consume_frame(frame = %Frame.Priority{}, state) do
    IO.inspect("Ignoring priority frame")
    IO.inspect(frame)
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
  def consume_frame(frame = %Frame.PushPromise{}, state) do
    {:error, {:protocol_error, "Clients cannot send push promises"}}
  end
  def consume_frame(frame = %Frame.RstStream{}, state) do
    IO.inspect("Ignoring rst_stream frame")
    IO.inspect(frame)
    {[], state}
  end
  def consume_frame(frame = %Frame.Headers{}, state) do
    # TODO pass through end stream flag
    if frame.end_headers do
      request = HPack.decode(frame.header_block_fragment, state.decode_context)
      |> Request.from_headers()
      state = dispatch(frame.stream_id, request, state)
      {[], state}
    else
      {[], %{state | next: {:continuation, frame.stream_id, frame.header_block_fragment}}}
    end
  end
  def consume_frame(frame = %Frame.Continuation{}, state = %{next: {:continuation, _stream_id, buffer}}) do
    buffer = buffer <> frame.header_block_fragment
    if frame.end_headers do
      request = HPack.decode(buffer, state.decode_context)
      |> Request.from_headers()
      state = dispatch(frame.stream_id, request, state)
      {[], state}
    else
      {[], %{state | next: {:continuation, frame.stream_id, buffer}}}
    end
  end
  def consume_frame(frame = %Frame.Data{}, state) do
    state = dispatch(frame.stream_id, frame.data, state)
    {[], state}
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

  def send_to_client({:conn, pid, id}, message) do
    send(pid, {:stream, id, message})
  end
  def dispatch(stream_id, headers = %{method: _}, state) do
    stream = case Map.get(state.streams, stream_id) do
      nil ->
        # DEBT try/catch assume always returns check with dialyzer
        handler = try do
          handler = state.router.route(headers)
        rescue
          e in FunctionClauseError ->
            # TODO implement DefaultHandler
            DefaultHandler
        end
        # handler = HomePage
        stream_spec = stream_spec(stream_id, handler, state)
        {:ok, pid} = Supervisor.start_child(state.stream_supervisor, stream_spec)
        ref = Process.monitor(pid)
        stream = {ref, pid}
      {ref, pid} ->
        {ref, pid}
    end
    {ref, pid} = stream
    # Maybe send with same ref as used for reply
    send(pid, {:headers, headers})
    streams = Map.put(state.streams, stream_id, stream)
    %{state | streams: streams}
  end
  def dispatch(stream_id, data, state) when is_binary(data) do
    {:ok, {_ref, pid}} = Map.fetch(state.streams, stream_id)
    send(pid, {:data, data})
    state
  end

  def stream_spec(id, handler, %{config: config}) do
    Supervisor.Spec.worker(handler, [{:conn, self(), id}, config], [restart: :temporary, id: id])
  end
end
