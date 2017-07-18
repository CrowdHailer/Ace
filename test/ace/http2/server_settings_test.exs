defmodule Ace.HTTP2.ServerSettingsTest do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Frame
  }

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
      Frame.Settings.new() |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Frame.Settings{ack: true}} == Support.read_next(connection)
    {:ok, %{client: connection}}
  end

  def route(_) do
    __MODULE__
  end


  # TODO diff given settings with defaults and only send changed
  # TODO start server with a max frame size and check it is sent to client and reflected in behaviour
  test "when no server settings are chosen frame size is default", %{client: connection} do
    bit_size = 16_385 * 8
    frame = Frame.Data.new(1, <<0::size(bit_size)>>, false)

    :ok = Support.send_frame(connection, frame)

    assert {:ok, frame = %Frame.GoAway{}} = Support.read_next(connection)
    assert "Frame greater than max allowed: (16384)" = frame.debug
    assert :frame_size_error = frame.error
  end

  # send incorrectly sized rst_stream frame


end
