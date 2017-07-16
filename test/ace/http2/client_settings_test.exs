defmodule Ace.HTTP2ClientSettingsTest do
  use ExUnit.Case

  alias Ace.HTTP2.Frame

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
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.Frame.Settings.new() |> Ace.HTTP2.Frame.Settings.serialize(),
    ]
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)
    :ssl.send(connection, payload)
    assert {:ok, %Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Frame.Settings{ack: true}} == Support.read_next(connection)
    {:ok, %{client: connection}}
  end

  def route(_) do
    __MODULE__
  end

  test "setting the max frame size to less than 16,384 is a protocol error", %{client: connection} do
    buffer = Frame.Settings.new(max_frame_size: 15_000) |> Ace.HTTP2.Frame.Settings.serialize()
    :ssl.send(connection, buffer)
    assert {:ok, %{debug: message}} = Support.read_next(connection)
    assert "max_frame_size too small" = message
  end
end
