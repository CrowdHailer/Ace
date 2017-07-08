defmodule Ace.HTTP2SetupTest do
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
      alpn_advertised_protocols: ["h2"]])
      :ssl.negotiated_protocol(connection)
    {:ok, %{client: connection}}
  end

  # Stream.fresh

  test "server sends settings as soon as connected", %{client: connection} do
    assert {:ok, Ace.HTTP2.settings_frame()} == :ssl.recv(connection, 0)
  end

  test "empty settings are acked", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)
  end

  test "sending settings", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(header_table_size: 200),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)
  end


  # send short ping
  # send long ping
  test "ping will be acked", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)
    assert <<8::24, 6::8, 0::8, 0::32, 1_000::64>> == Ace.HTTP2.ping_frame(<<1_000::64>>)
    :ssl.send(connection, Ace.HTTP2.ping_frame(<<1_000::64>>))
    assert {:ok, Ace.HTTP2.ping_frame(<<1_000::64>>, ack: true)} == :ssl.recv(connection, 0, 2_000)
  end

  test "send window update", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)

    :ssl.send(connection, <<4::24, 8::8, 0::8, 0::32, 1::32>>)
    Process.sleep(2_000)
    # TODO send data down
    # assert {:ok, <<8::24, 6::8, 0::8, 1::32, 1_000::64>>} == :ssl.recv(connection, 9, 2_000)
  end

# Can't send a headers frame with stream id odd for server
  test "send get request", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)

    {:ok, table} = HPack.Table.start_link(1_000)
    body = HPack.encode([{":method", "GET"}, {":scheme", "https"}, {":path", "/"}], table)

    size = :erlang.iolist_size(body)

    flags = <<0::5, 1::1, 0::1, 1::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    Process.sleep(2_000)
    # 200 response with body "Hello, World!"
    assert {:ok, <<0, 0, 1, 1, 4, 0, 0, 0, 1, 136, 0, 0, 13, 0, 1, 0, 0, 0, 1, 72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33>>} == :ssl.recv(connection, 0, 2_000)
  end

  test "send post with data", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)

    {:ok, table} = HPack.Table.start_link(1_000)
    body = HPack.encode([{":method", "POST"}, {":scheme", "https"}, {":path", "/"}], table)

    size = :erlang.iolist_size(body)

    # <<_, _, priority, _, padded, end_headers, _, end_stream>>
    flags = <<0::5, 1::1, 0::1, 0::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    data_frame = Ace.HTTP2.data_frame(1, "Upload", end_stream: true)
    :ssl.send(connection, data_frame)
    Process.sleep(2_000)
    # TODO test a 201 comes back
  end

  test "send post with padded data", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)

    {:ok, table} = HPack.Table.start_link(1_000)
    body = HPack.encode([{":method", "POST"}, {":scheme", "https"}, {":path", "/"}], table)

    size = :erlang.iolist_size(body)

    # <<_, _, priority, _, padded, end_headers, _, end_stream>>
    flags = <<0::5, 1::1, 0::1, 0::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    data_frame = Ace.HTTP2.data_frame(1, "Upload", pad_length: 2, end_stream: true)
    :ssl.send(connection, data_frame)
    Process.sleep(2_000)
  end

end
