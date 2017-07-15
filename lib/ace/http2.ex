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
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @default_settings %{}

  def preface() do
    @preface
  end

  def data_frame(stream_id, data, opts \\ []) do
    type = <<0>>
    pad_length = Keyword.get(opts, :pad_length)
    payload = case pad_length do
      nil ->
        data
      pad_length when 0 <= pad_length and pad_length <= 255 ->
        pad_bit_lenth = pad_length * 8
        <<pad_length::8, data::binary, 0::size(pad_bit_lenth)>>
    end
    size = :erlang.iolist_size(payload)
    padded_flag = if pad_length, do: 1, else: 0
    end_stream_flag = if Keyword.get(opts, :end_stream), do: 1, else: 0
    flags = <<0::4, padded_flag::1, 0::2, end_stream_flag::1>>
    <<size::24, type::binary, flags::binary, 0::1, stream_id::31, payload::binary>>
  end

  defmodule Settings do
    defstruct [
      header_table_size: nil,
      enable_push: nil,
      max_concurrent_streams: nil,
      initial_window_size: nil,
      max_frame_size: nil,
      max_header_list_size: nil
    ]
  end

  def settings_frame(parameters \\ []) do
    # struct(Settings, parameters) Can use required values
    type = 4
    flags = 0
    stream_id = 0
    payload = Ace.HTTP2.Frame.Settings.parameters_to_payload(parameters)
    size = :erlang.iolist_size(payload)
    <<size::24, type::8, flags::8, 0::1, stream_id::31, payload::binary>>
  end

  defstruct [
    # next: :preface, :settings, :continuation, :any
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
    :ssl.send(socket, settings_frame())
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
    consume(data, state)
  end
  def handle_info({:stream, stream_id, {:headers, headers}}, state) do
    IO.inspect(headers)
    headers_payload = encode_response_headers(headers, state.encode_context)
    headers_size = :erlang.iolist_size(headers_payload)
    headers_flags = <<0::5, 1::1, 0::1, 0::1>>
    header = <<headers_size::24, 1::8, headers_flags::binary, 0::1, 1::31, headers_payload::binary>>
    :ok = :ssl.send(state.socket, header)
    {:noreply, state}
  end
  def handle_info({:stream, stream_id, {:data, {data_payload, :end}}}, state) do
    IO.inspect(data_payload)
    data = data_frame(stream_id, data_payload, end_stream: true)
    :ok = :ssl.send(state.socket, data)
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
    {frame, unprocessed} = Ace.HTTP2.Frame.parse_from_buffer(buffer) # + state.settings )
    if frame do
      case Ace.HTTP2.Frame.decode(frame) do
        {:ok, frame} ->
          IO.inspect(frame)
          # Could consume with only settings
          case consume_frame(frame, state) do
            {outbound, state} when is_list(outbound) ->
              :ok = :ssl.send(state.socket, outbound)
              consume(unprocessed, state)
            {:error, error} when is_atom(error) ->
              frame = Ace.HTTP2.Frame.GoAway.new(0, error)
              outbound = Ace.HTTP2.Frame.GoAway.serialize(frame)
              :ok = :ssl.send(state.socket, outbound)
              # Despite being an error the connection has successfully dealt with the client and does not need to crash
              {:stop, :normal, state}
            {:error, {error, debug}} ->
              frame = Ace.HTTP2.Frame.GoAway.new(0, error, debug)
              outbound = Ace.HTTP2.Frame.GoAway.serialize(frame)
              :ok = :ssl.send(state.socket, outbound)
              # Despite being an error the connection has successfully dealt with the client and does not need to crash
              {:stop, :normal, state}
          end
        {:error, {error, debug}} ->
          frame = Ace.HTTP2.Frame.GoAway.new(0, error, debug)
          outbound = Ace.HTTP2.Frame.GoAway.serialize(frame)
          :ok = :ssl.send(state.socket, outbound)
          # Despite being an error the connection has successfully dealt with the client and does not need to crash
          {:stop, :normal, state}
      end


    else
      :ssl.setopts(state.socket, [active: :once])
      {:noreply, state}
    end
  end

  # def consume_frame(@settings, 0, flags, length, payload, %{next: :setup})
  # def consume_frame(%Settings{ack: false, parameters: parameters}, state = %{next: setup})

  alias Ace.HTTP2.Frame

  # settings
  def consume_frame(settings = %Ace.HTTP2.Frame.Settings{}, state = %{settings: nil}) do
    new_settings = update_settings(settings)
    {[<<0::24, 4::8, 1::8, 0::32>>], %{state | settings: new_settings}}
  end
  def consume_frame(_, state = %{settings: nil}) do
    {:error, {:protocol_error, "Did not receive settings frame"}}
  end
  # Consume settings ack make sure we are not in a state of settings nil
  # def consume_frame({4, <<1>>, 0, ""}, state = %{settings: %{}}) do
  #   {[], state}
  # end
  def consume_frame(%Frame.Ping{identifier: data, ack: false}, state) do
    {[<<8::24, 6::8, 1::8, 0::32, data::binary>>], state}
  end
  # Window update
  def consume_frame(%Frame.WindowUpdate{stream_id: 0}, state) do
    IO.inspect("total window update")
    {[], state}
  end
  # Window update
  def consume_frame(%Frame.WindowUpdate{stream_id: _}, state) do
    IO.inspect("Stream window update")
    {[], state}
  end
  # headers
  defmodule Request do
    # @enforce_keys [:scheme, :authority, :method, :path, :headers]
    defstruct [:scheme, :authority, :method, :path, :headers]

    def to_headers(request = %__MODULE__{}) do
      [
        {":scheme", Atom.to_string(request.scheme)},
        {":authority", request.authority},
        {":method", Atom.to_string(request.method)},
        {":path", request.path} |
        Map.to_list(request.headers)
      ]
    end

    def from_headers(headers) do
      headers
      |> Enum.reduce(%__MODULE__{}, &add_header/2)
    end

    def add_header({":method", method}, request = %{method: nil}) do
      %{request | method: method}
    end
    def add_header({":path", path}, request = %{path: nil}) do
      %{request | path: path}
    end
    def add_header({":scheme", scheme}, request = %{scheme: nil}) do
      %{request | scheme: scheme}
    end
    def add_header({":authority", authority}, request = %{authority: nil}) do
      %{request | authority: authority}
    end
    def add_header({key, value}, request = %{headers: headers}) do
      # TODO test key does not begin with `:`
      headers = Map.put(headers || %{}, key, value)
      %{request | headers: headers}
    end
  end
  def consume_frame(frame = %Frame.Headers{}, state) do
    request = HPack.decode(frame.header_block_fragment, state.decode_context)
    |> Request.from_headers()
    state = dispatch(frame.stream_id, request, state)
    {[], state}
  end
  def consume_frame(frame = %Frame.Data{}, state) do
    state = dispatch(frame.stream_id, frame.data, state)
    {[], state}
  end

  def update_settings(new, old \\ @default_settings) do
    IO.inspect(new)
    %{}
  end

  def send_to_client({:conn, pid, id}, message) do
    send(pid, {:stream, id, message})
  end
  def dispatch(stream_id, headers = %{method: _}, state) do
    stream = case Map.get(state.streams, stream_id) do
      nil ->
        handler = state.router.route(headers)
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
  def dispatch(stream_id, data, state) do
    {:ok, {_ref, pid}} = Map.fetch(state.streams, stream_id)
    send(pid, {:data, data})
    state
  end

  def stream_spec(id, handler, %{config: config}) do
    Supervisor.Spec.worker(handler, [{:conn, self(), id}, config], [restart: :temporary, id: id])
  end
end
