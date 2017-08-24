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

  def read_next(connection, timeout \\ 5_000) do
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
