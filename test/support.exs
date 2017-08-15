defmodule RaxxForwarder do
  def handle_request(request, pid) do
    {:ok, response} = GenServer.call(pid, request)
    response
  end
end

defmodule Support do
  def test_certfile() do
    Path.expand("ace/tls/cert.pem", __DIR__)
  end

  def test_keyfile() do
    Path.expand("ace/tls/key.pem", __DIR__)
  end

  def next_worker_self do
    receive do
      {:"$gen_call", from, {:start_child, []}} ->
        GenServer.reply(from, {:ok, self()})
    after
      1_000 ->
        {:error, :no_call}
    end
  end

  def read_next(connection, timeout \\ :infinity) do
    case :ssl.recv(connection, 9, timeout) do
      {:ok, <<length::24, type::8, flags::binary-size(1), 0::1, stream_id::31>>} ->
        case length do
          0 ->
            Ace.HTTP2.Frame.decode({type, flags, stream_id, ""})
          length ->
            {:ok, payload} = :ssl.recv(connection, length, timeout)
            Ace.HTTP2.Frame.decode({type, flags, stream_id, payload})
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_frame(connection, frame) do
    :ssl.send(connection, Ace.HTTP2.Frame.serialize(frame))
  end

  def start_server(stream_supervisor, port \\ 0) do
    certfile =  Path.expand("ace/tls/cert.pem", __DIR__)
    keyfile =  Path.expand("ace/tls/key.pem", __DIR__)
    options = [
      active: false,
      mode: :binary,
      packet: :raw,
      certfile: certfile,
      keyfile: keyfile,
      reuseaddr: true,
      alpn_preferred_protocols: ["h2", "http/1.1"]
    ]
    {:ok, listen_socket} = :ssl.listen(port, options)
    {:ok, server} = Ace.HTTP2.Server.start_link(listen_socket, stream_supervisor)
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {server, port}
  end

  def open_connection(port) do
    {:ok, connection} = :ssl.connect('localhost', port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)
    connection
  end

  def home_page_headers(rest \\ []) do
    [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ] ++ rest
  end
end
