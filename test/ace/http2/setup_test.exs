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
    {:ok, server} = Ace.HTTP2.start_link(listen_socket, {__MODULE__, %{test_pid: self}})
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {:ok, connection} = :ssl.connect('localhost', port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]])
      :ssl.negotiated_protocol(connection)
    {:ok, %{client: connection}}
  end

  def route(_) do
    __MODULE__
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

  test "incorrect ping frame is a connection error", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)
    malformed_frame = <<10::24, 6::8, 0::8, 0::32, 1_000::80>>
    :ssl.send(connection, malformed_frame)
    assert {:ok, Ace.HTTP2.go_away_frame(:protocol_error)} == :ssl.recv(connection, 0, 2_000)
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



end
