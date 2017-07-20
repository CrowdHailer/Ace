defmodule Ace.HTTP2Test do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Frame
  }

  def handle_request(_, _) do
    Raxx.Response.ok("Hello, World!", [{"content-length", "13"}])
  end

  test "start endpoint" do
    Ace.HTTP2.start_link(
      {Ace.HTTP2.Stream.RaxxHandler, {__MODULE__, :foo}},
      9999,
      certfile: Path.expand("../ace/tls/cert.pem", __DIR__),
      keyfile: Path.expand("../ace/tls/key.pem", __DIR__),
      connections: 3
    )
    {:ok, connection} = :ssl.connect('localhost', 9999, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)

    payload = [
      Ace.HTTP2.Connection.preface(),
      Ace.HTTP2.Frame.Settings.new() |> Ace.HTTP2.Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: true}} == Support.read_next(connection)

    {:ok, encode_table} = HPack.Table.start_link(1_000)
    headers = home_page_headers()
    header_block = HPack.encode(headers, encode_table)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)
    assert {:ok, %Frame.Headers{}} = Support.read_next(connection)
    assert {:ok, %Frame.Data{}} = Support.read_next(connection)
  end

  defp home_page_headers(rest \\ []) do
    [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ] ++ rest
  end
end
