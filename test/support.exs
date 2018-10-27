defmodule Raxx.Kaboom do
  use Raxx.SimpleServer

  @impl Raxx.SimpleServer
  def handle_request(_request, _config) do
    raise "Kaboom !!!"
  end
end

defmodule Support do
  def test_certfile() do
    Path.expand("ace/tls/cert.pem", __DIR__)
  end

  def test_keyfile() do
    Path.expand("ace/tls/key.pem", __DIR__)
  end

  def read_next(connection, timeout \\ 5000) do
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
    {:ok, connection} =
      :ssl.connect(
        'localhost',
        port,
        mode: :binary,
        packet: :raw,
        active: false,
        alpn_advertised_protocols: ["h2"]
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

defmodule Raxx.Forwarder do
  use Ace.HTTP.Service,
    port: 0,
    acceptors: 1,
    certfile: Support.test_certfile(),
    keyfile: Support.test_keyfile()

  @impl Raxx.Server
  def handle_head(request, state = %{target: pid}) do
    GenServer.call(pid, {:headers, request, state})
  end

  @impl Raxx.Server
  def handle_data(data, state = %{target: pid}) do
    GenServer.call(pid, {:data, data, state})
  end

  @impl Raxx.Server
  def handle_tail(tail, state = %{target: pid}) do
    GenServer.call(pid, {:tail, tail, state})
  end

  @impl Raxx.Server
  def handle_info({__MODULE__, :stop, reason}, _state) do
    Process.exit(self(), reason)
  end

  def handle_info(response, _state) do
    response
  end
end
