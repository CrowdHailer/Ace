defmodule Ace.HTTP2SetupTest do
  use ExUnit.Case

  setup do
    certfile =  Path.expand("../ace/tls/cert.pem", __DIR__)
    keyfile =  Path.expand("../ace/tls/key.pem", __DIR__)
    options = [
      active: false,
      mode: :binary,
      packet: :raw,
      certfile: certfile,
      keyfile: keyfile,
      reuseaddr: true,
      alpn_preferred_protocols: ["h2", "http/1.1"]
    ]
    {:ok, listen_socket} = :ssl.listen(0, options)
    {:ok, server} = Ace.HTTP2.start_link(listen_socket)
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {:ok, connection} = :ssl.connect('localhost', port, [
      mode: :binary,
      packet: :raw,
      active: :true,
      alpn_advertised_protocols: ["h2"]])
      :ssl.negotiated_protocol(connection)
    {:ok, %{client: connection}}
  end

  test "a single get request", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      <<0::24, 4::8, 0::8, 0::32>>,
    ]
    :ssl.send(connection, payload)
    assert_receive 5, 1_000
    Process.sleep(5_000)
  end
end
