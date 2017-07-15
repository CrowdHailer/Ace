defmodule Ace.HTTP2PingTest do
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
    {:ok, _server} = Ace.HTTP2.start_link(listen_socket, {__MODULE__, %{test_pid: self()}})
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

  alias Ace.HTTP2.Frame

  test "ping will be acked", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, <<0::24, 4::8, 1::8, 0::32>>} == :ssl.recv(connection, 9)
    ping_frame = Frame.Ping.new(<<1_000::64>>)
    :ssl.send(connection, Frame.Ping.serialize(ping_frame))
    assert {:ok, Frame.Ping.serialize(Frame.Ping.ack(ping_frame))} == :ssl.recv(connection, 0, 2_000)
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

end
