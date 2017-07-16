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

  alias Ace.HTTP2.{
    Frame
  }
  # Stream.fresh

  test "server sends settings as soon as connected", %{client: connection} do
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)
  end

  test "client must first send settings frame", %{client: connection} do
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)
    payload = [
      Ace.HTTP2.preface(),
      Frame.Ping.new(<<0::64>>) |> Frame.Ping.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Frame.GoAway{debug: _}} = Support.read_next(connection)
  end

  test "empty settings are acked", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Frame.Settings.new() |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
  end

  test "sending settings", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Frame.Settings.new(header_table_size: 200) |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
  end

  test "send window update", %{client: connection} do
    payload = [
      Ace.HTTP2.preface(),
      Frame.Settings.new() |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)

    :ssl.send(connection, <<4::24, 8::8, 0::8, 0::32, 1::32>>)
    Process.sleep(2_000)
    # TODO send data down
  end

# Can't send a headers frame with stream id odd for server



end
