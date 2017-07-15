defmodule Ace.HTTP2RoutingTest do
  use ExUnit.Case

  setup do
    certfile =  Path.expand("../../ace/tls/cert.pem", __DIR__)
    keyfile =  Path.expand("../../ace/tls/key.pem", __DIR__)
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
    {:ok, server} = Ace.HTTP2.start_link(listen_socket, %{test_pid: self})
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {:ok, connection} = :ssl.connect('localhost', port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    :ssl.negotiated_protocol(connection)
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, <<0::24, 4::8, 0::8, 0::32>>} == :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)
    {:ok, %{client: connection}}
  end

  alias Ace.HTTP2.Request

  # Sending without required header is an error
  test "sending unpadded headers", %{client: connection} do
    request = %Request{
      scheme: :https,
      authority: "example.com",
      method: :GET,
      path: "/",
      headers: %{"content-length" => "0"}
    }

    headers = Request.to_headers(request)
    |> IO.inspect
    {:ok, table} = HPack.Table.start_link(1_000)
    header_block_fragment = HPack.encode(headers, table)
    |> IO.inspect

    size = :erlang.iolist_size(header_block_fragment)

    flags = <<0::5, 1::1, 0::1, 1::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, header_block_fragment::binary>>)
    Process.sleep(2_000)
    # 200 response with header_block_fragment "Hello, World!"
    assert {:ok, data} = :ssl.recv(connection, 0, 2_000)
    # TODO test headers
    assert {{1, _, 1, _}, ""} = Ace.HTTP2.Frame.parse_from_buffer(data)

    assert {:ok, <<0, 0, 13, 0, 1, 0, 0, 0, 1, 72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33>>} == :ssl.recv(connection, 0, 2_000)
  end

  test "sending padded headers", %{client: connection} do
    request = %Request{
      scheme: :https,
      authority: "example.com",
      method: :GET,
      path: "/",
      headers: %{"content-length" => "0"}
    }

    headers = Request.to_headers(request)
    |> IO.inspect
    {:ok, table} = HPack.Table.start_link(1_000)
    header_block_fragment = HPack.encode(headers, table)
    |> IO.inspect

    payload = Ace.HTTP2.Frame.pad_data(header_block_fragment, 2)

    size = :erlang.iolist_size(payload)

    flags = <<0::4, 1::1, 1::1, 0::1, 1::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, payload::binary>>)
    Process.sleep(2_000)
    # 200 response with header_block_fragment "Hello, World!"
    assert {:ok, data} = :ssl.recv(connection, 0, 2_000)
    # TODO test headers
    assert {{1, _, 1, _}, ""} = Ace.HTTP2.Frame.parse_from_buffer(data)
    assert {:ok, <<0, 0, 13, 0, 1, 0, 0, 0, 1, 72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33>>} == :ssl.recv(connection, 0, 2_000)
  end
end
