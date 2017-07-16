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
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.Frame.Settings.new() |> Ace.HTTP2.Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: true}} == Support.read_next(connection)
    {:ok, %{client: connection}}
  end

  def route(_) do
    __MODULE__
  end

  alias Ace.HTTP2.Frame

  test "ping will be acked", %{client: connection} do
    identifier = <<1_000::64>>
    ping_frame = Frame.Ping.new(identifier)
    :ssl.send(connection, Frame.Ping.serialize(ping_frame))
    assert {:ok, %Frame.Ping{ack: true, identifier: identifier}} == Support.read_next(connection)
  end

  test "incorrect ping frame is a connection error", %{client: connection} do
    malformed_frame = %Frame.Ping{identifier: <<1_000::80>>, ack: false}
    :ssl.send(connection, Frame.Ping.serialize(malformed_frame))
    # TODO check that last stream id is correct
    expected_frame = Frame.GoAway.new(1, :frame_size_error)
    payload = Frame.GoAway.payload(expected_frame)
    assert {:ok, %Frame.GoAway{error: 6, debug: debug}} = Support.read_next(connection)
    assert "Ping identifier must be 64 bits" == debug
  end

  # send acked ping
  # send bad ping expecting stream_id > 0

end
