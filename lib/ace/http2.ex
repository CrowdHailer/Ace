defmodule Ace.HTTP2 do
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @default_settings %{}

  def preface() do
    @preface
  end

  def data_frame(stream_id, data, opts) do
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
    payload = parameters_to_payload(parameters)
    size = :erlang.iolist_size(payload)
    <<size::24, type::8, flags::8, 0::1, stream_id::31, payload::binary>>
  end

  def parameters_to_payload(parameters, payload \\ [])
  def parameters_to_payload([], payload) do
    Enum.reverse(payload)
    |> :erlang.iolist_to_binary
  end
  def parameters_to_payload([{:header_table_size, value} | rest], payload) do
    payload = [<<1::16, value::32>> | payload]
    parameters_to_payload(rest, payload)
  end

  def ping_frame(identifier, opts \\ []) when byte_size(identifier) == 8 do
    type = <<6>>
    flags = if Keyword.get(opts, :ack, false), do: <<1>>, else: <<0>>
    <<8::24, type::binary, flags::binary, 0::1, 0::31, identifier::binary>>
  end

  def go_away_frame(:protocol_error) do
    type = 7
    last_stream_id = 1 # TODO
    error_code = 1
    debug_message = ""

    payload = <<0::1, last_stream_id::31, error_code::32, debug_message::binary>>
    size = :erlang.iolist_size(payload)

    type = 7
    <<size::24, type::8, 0::8, 0::1, 0::31, payload::binary>>
  end

  defstruct [
    # next: :preface, :settings, :continuation, :any
    settings: nil,
    socket: nil,
    decode_context: nil,
    encode_context: nil,
    streams: nil,
    config: nil,
    stream_supervisor: nil
  ]

  use GenServer
  def start_link(listen_socket, config) do
    GenServer.start_link(__MODULE__, {listen_socket, config})
  end

  def init({listen_socket, config}) do
    {:ok, {:listen_socket, listen_socket, config}, 0}
  end
  def handle_info(:timeout, {:listen_socket, listen_socket, config}) do
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
    {frame, unprocessed} = Ace.HTTP2.Frame.read_next(buffer) # + state.settings )
    if frame do
      # Could consume with only settings
      case consume_frame(frame, state) do
        {outbound, state} when is_list(outbound) ->
          :ok = :ssl.send(state.socket, outbound)
          consume(unprocessed, state)
        {:error, :protocol_error} ->
          outbound = go_away_frame(:protocol_error)
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

  # settings
  def consume_frame(<<l::24, 4::8, 0::8, 0::1, 0::31, payload::binary>>, state = %{settings: nil}) do
    new_settings = update_settings(payload)
    {[<<0::24, 4::8, 1::8, 0::32>>], %{state | settings: new_settings}}
  end
  def consume_frame(_, state = %{settings: nil}) do
    :invalid_first_frame
  end
  # ping
  def consume_frame(<<8::24, 6::8, 0::8, 0::32, data::64>>, state) do
    {[<<8::24, 6::8, 1::8, 0::32, data::64>>], state}
  end
  def consume_frame(<<l::24, 6::8, 0::8, 0::32, data::binary-size(l)>>, state) do
    {:error, :protocol_error}
  end
  # Window update
  def consume_frame(<<4::24, 8::8, 0::8, 0::32, data::32>>, state) do
    {[], state}
  end
  def consume_frame(<<_::24, 2::8, f::8, 0::1, stream_id::31, data::binary>>, state) do
    IO.inspect("priority for stream #{stream_id}, #{data |> inspect}")
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
  def consume_frame(<<_::24, 1::8, flags::bits-size(8), 0::1, stream_id::31, payload::binary>>, state) do
    <<_::1, _::1, priority::1, _::1, padded::1, end_headers::1, _::1, end_stream::1>> = flags
    IO.inspect(priority)
    IO.inspect(padded)
    IO.inspect(end_headers)
    IO.inspect(end_stream)

    data = if padded == 1 do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end

    case flags do

      <<_::5, 1::1, 0::1, 1::1>> ->
        IO.inspect(data, limit: :infinity)
        request = HPack.decode(data, state.decode_context)
        |> Request.from_headers()
        state = dispatch(stream_id, request, state)
        {[], state}
      <<_::5, 1::1, 0::1, 0::1>> ->
        IO.inspect("needs data")
        IO.inspect(data)
        request = HPack.decode(data, state.decode_context)
        |> Request.from_headers()
        state = dispatch(stream_id, request, state)
        {[], state}
    end
  end
  def consume_frame(<<length::24, 0::8, flags::bits-size(8), 0::1, stream_id::31, payload::binary>>, state) do
    <<_::4, padded_flag::1, _::2, end_data_flag::1>> = flags
    data = if padded_flag == 1 do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end
    state = dispatch(stream_id, data, state)
    {[], state}
  end

  def update_settings(new, old \\ @default_settings) do
    IO.inspect(new |> parse_settings)
    %{}
  end

  def parse_settings(binary, data \\ %{})
  def parse_settings(<<>>, data) do
    {:ok, data}
  end
  def parse_settings(<<1::16, value::32, rest::binary>>, data) do
    data = Map.put(data, :header_table_size, value)
    parse_settings(rest, data)
  end
  def parse_settings(<<4::16, value::32, rest::binary>>, data) do
    data = Map.put(data, :initial_window_size, value)
    parse_settings(rest, data)
  end
  def parse_settings(<<5::16, value::32, rest::binary>>, data) do
    data = Map.put(data, :max_frame_size, value)
    parse_settings(rest, data)
  end



  defmodule HomePage do
    use GenServer

    def start_link(connection, config) do
      GenServer.start_link(__MODULE__, {connection, config})
    end

    # Maybe we want to use a GenServer.call when passing messages back to connection for back pressure.
    # Need to send back a reference to the stream_id
    def handle_info({:headers, request}, {connection, config}) do
      IO.inspect(request)
      # Connection.stream({pid, ref}, headers/data/push or update etc)

      Ace.HTTP2.send_to_client(connection, {:headers, %{status: 200}})
      Ace.HTTP2.send_to_client(connection, {:data, {"Hello, World!", :end}})
      {:noreply, {connection, config}}
    end


  end

  defmodule CreateAction do
    use GenServer

    def start_link(connection, config) do
      GenServer.start_link(__MODULE__, {connection, config})
    end

    def handle_info({:headers, request}, {connection, config}) do
      IO.inspect(request)
      {:noreply, {connection, config}}
    end

    def handle_info({:data, data}, {connection, config}) do
      IO.inspect("data")
      IO.inspect(data)
      Ace.HTTP2.send_to_client(connection, {:headers, %{:status => 201, "content-length" => "0"}})
      {:noreply, {connection, config}}
    end

  end

  def send_to_client({:conn, pid, id}, message) do
    send(pid, {:stream, id, message})
  end
  def dispatch(stream_id, headers = %{method: _}, state) do
    stream = case Map.get(state.streams, stream_id) do
      nil ->
        handler = route(headers)
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

  def route(%{method: "GET", path: "/"}) do
    HomePage
  end
  def route(%{method: "POST", path: "/"}) do
    CreateAction
  end

  def stream_spec(id, handler, %{config: config}) do
    Supervisor.Spec.worker(handler, [{:conn, self(), id}, config], [restart: :temporary, id: id])
  end
end
