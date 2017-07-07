defmodule Ace.HTTP2 do
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @default_settings %{}

  def preface() do
    @preface
  end

  defstruct [
    # next: :preface, :settings, :continuation, :any
    settings: nil,
    socket: nil,
    decode_context: nil,
    encode_context: nil,
    streams: nil,
    config: nil
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
    :ssl.send(socket, <<0::24, 4::8, 0::8, 0::32>>)
    :ssl.setopts(socket, [active: :once])
    {:ok, decode_context} = HPack.Table.start_link(1_000)
    {:ok, encode_context} = HPack.Table.start_link(1_000)
    initial_state = %__MODULE__{
      socket: socket,
      decode_context: decode_context,
      encode_context: encode_context,
      streams: %{},
      config: config
    }
    {:noreply, {:pending, initial_state}}
  end
  def handle_info({:ssl, _, @preface <> data}, {:pending, state}) do
    consume(data, state)
  end
  def handle_info({:ssl, _, data}, state = %__MODULE__{}) do
    consume(data, state)
  end

  def consume(buffer, state) do
    {frame, unprocessed} = Ace.HTTP2.Frame.read_next(buffer) # + state.settings )
    # IO.inspect(frame)
    # IO.inspect(unprocessed)
    if frame do
      # Could consume with only settings
      {outbound, state} = consume_frame(frame, state)
      :ok = :ssl.send(state.socket, outbound)
      consume(unprocessed, state)
    else
      :ssl.setopts(state.socket, [active: :once])
      {:noreply, state}
    end
  end

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
  # Window update
  def consume_frame(<<4::24, 8::8, 0::8, 0::32, data::32>>, state) do
    {[], state}
  end
  # headers
  defmodule Request do
    defstruct [:method, :path, :scheme, :headers]
  end
  def consume_frame(<<_::24, 1::8, flags::bits-size(8), 0::1, stream_id::31, data::binary>>, state) do
    case flags do

      <<0::5, 1::1, 0::1, 1::1>> ->
        request = HPack.decode(data, state.decode_context)
        |> Enum.reduce(%Request{}, &add_header/2)
        {frames, streams} = dispatch(stream_id, request, state.streams, state.config)
        # Note state must be binary
        headers_payload = HPack.encode([{":status", "200"}], state.encode_context)
        headers_size = :erlang.iolist_size(headers_payload)
        headers_flags = <<0::5, 1::1, 0::1, 0::1>>
        header = <<headers_size::24, 1::8, headers_flags::binary, 0::1, 1::31, headers_payload::binary>>
        data_payload = "Hello, World!"
        data_size = :erlang.iolist_size(data_payload)
        data = <<data_size::24, 0::8, 1::8, 0::1, 1::31, data_payload::binary>>
        state = %{state | streams: streams}
        {[header, data], state}
      <<0::5, 1::1, 0::1, 0::1>> ->
        IO.inspect("needs data")
        request = HPack.decode(data, state.decode_context)
        |> Enum.reduce(%Request{}, &add_header/2)
        {frames, streams} = dispatch(stream_id, request, state.streams, state.config)
        {[], state}
    end
  end
  def consume_frame(<<length::24, 0::8, flags::bits-size(8), 0::1, stream_id::31, payload::binary>>, state) do
    <<_::4, padded_flag::1, _::2, end_data_flag::1>> = flags
    data = if padded_flag == 1 do
      <<pad_length, rest::binary>> = payload
      data_length = length - pad_length - 1
      <<data::binary-size(data_length), _zero_padding::binary-size(pad_length)>> = rest
      data
    else
      payload
    end
    {frames, streams} = dispatch(stream_id, data, state.streams, state.config)
    state = %{state | streams: streams}
    {[], state}
  end

  def update_settings(new, old \\ @default_settings) do
    IO.inspect(new)
    %{}
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

  defmodule Stream do
    def idle(config) do
      %{state: config}
    end

    def dispatch(stream = %{state: state}, request = %{method: _}) do
      response = handle_request(request, state)
      {response, stream}
    end
    def dispatch(stream = %{state: state}, data) when is_binary(data) do
      response = handle_data(data, state)
      {response, stream}
    end

    def handle_request(%{method: "GET", path: "/"}, state) do
      [%{status: 200}, "Hello world!", :end]
    end
    def handle_request(%{method: "POST", path: "/"}, state) do
      []
    end
    def handle_data(data, state) do
      IO.inspect(state)
      []
    end

  end
  def dispatch(stream_id, request, streams, config) do
    stream = Map.get(streams, stream_id, Stream.idle(config))
    {response, stream} = Stream.dispatch(stream, request)
    streams = Map.put(streams, stream_id, stream)
    {response, streams}
  end

  #
  # def ready do
  #   receive do
  #     {:"$gen_server", from, {:accept, socket}} ->
  #       :ssl.accept
  #   end
  # end
  #
  # def loop(state = %{socket: socket}) do
  #
  #   receive do
  #     {ACE, frame} ->
  #       {:ok, frames} = constrain_frame(frame, state.settings)
  #       state = %{state | outbound: state.outbound ++ frames}
  #     {:ssl, ^socket, data} ->
  #       {buffer, state} = read_frames(buffer <> data, state)
  #       loop(buffer, state)
  #   end
  # end
  #
  # def do_read_frames(buffer, state, socket) do
  #   {pending, state} = read_frames(buffer, state)
  #   expediate(pending, state, socket)
  #   do_read_frames(buffer, state, socket)
  # end
  #
  # def read_frames(buffer, state) do
  #   case Frame.pop(data) do
  #     {:ok, {nil, buffer}} ->
  #       {buffer, state}
  #     {:ok, {frame, buffer}} ->
  #       {pending, state} = handle_frame(frame, state)
  #       read_frames(buffer, state)
  #   end
  # end
  #
  #
  # def handle_frame(new = %Settings{}, %{settings: nil}) do
  #   update_settings(new, nil)
  # end
  # def handle_frame(_, %{settings: nil}) do
  #   # Unexpected frame for startup
  # end
  #
  # def handle_frame(frame = %Headers{fin: true}, state) do
  #   # start_stream(state.stream_supervisor)
  #   {:ok, pid} = start_link(Ace.Stream, :init, [[frame]])
  #   streams = Map.put(state.streams, frame.stream_id, pid)
  # end
  # def handle_frame(frame = %Headers{fin: false}, state) do
  #   {[], %{state | stream_head: [frame]}}
  # end
  # def handle_frame(frame = %Continuation{fin: true}, state) do
  #   stream_head = state.
  # end
  # def handle_frame(frame = %Data{}, state) do
  #   {:ok, pid} = fetch_stream(frame, state)
  #   Stream.send_data(pid, frame)
  # end
  #
  # def start_stream(head = {:GET, "/foo", _ip}) do
  #   # start under dynamic supervisor
  #   Ace.FooController.start_link(head)
  #   {:ok, pid} = start_link(Ace.FooController, :init, [[frame]])
  #
  # end


end
