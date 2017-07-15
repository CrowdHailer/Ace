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
      Ace.HTTP2.settings_frame(),
    ]
    :ssl.send(connection, payload)
    :ssl.recv(connection, 9)
    assert {:ok, {4, <<1>>, 0, ""}} == read_next(connection)
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
    assert {:ok, {6, <<1>>, 0, identifier}} == read_next(connection)
  end

  test "incorrect ping frame is a connection error", %{client: connection} do
    malformed_frame = %Frame.Ping{identifier: <<1_000::80>>, ack: false}
    :ssl.send(connection, Frame.Ping.serialize(malformed_frame))
    # TODO check that last stream id is correct
    assert {:ok, {7, <<0>>, 0, Frame.GoAway.payload(1, :protocol_error)}} == read_next(connection)
  end

  # send acked ping
  # send bad ping expecting stream_id > 0

  def read_next(connection) do
    case :ssl.recv(connection, 9) do
      {:ok, <<length::24, type::8, flags::binary-size(1), 0::1, stream_id::31>>} ->
        case length do
          0 ->
            {:ok, {type, flags, stream_id, ""}}
          length ->
            {:ok, payload} = :ssl.recv(connection, length)
            {:ok, {type, flags, stream_id, payload}}
        end
    end
  end

end
