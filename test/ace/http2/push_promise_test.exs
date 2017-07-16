defmodule Ace.HTTP2.PushPromiseTest do
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

  test "sending a push promise from a client is a protocol error", %{client: connection} do
    priority_frame = Frame.PushPromise.new(2, 1, "header_block_fragment")
    |> IO.inspect
    :ssl.send(connection, Frame.PushPromise.serialize(priority_frame) |> IO.inspect)
    assert {:ok, %Frame.GoAway{debug: debug}} = Support.read_next(connection, 2_000)
    assert "Clients cannot send push promises" = debug
  end



end
