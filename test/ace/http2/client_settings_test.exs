defmodule Ace.HTTP2ClientSettingsTest do
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

  test "setting the max frame size to less than 16,384 is a protocol error", %{client: connection} do
    assert {:ok, Ace.HTTP2.settings_frame()} == :ssl.recv(connection, 0)
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.settings_frame(max_frame_size: 15000),
    ]
    :ssl.send(connection, payload)
    assert {:ok, data} = :ssl.recv(connection, 0)
    {frame, ""} = Ace.HTTP2.Frame.parse_from_buffer(data)
    # assert {7, _, 0, <<_::32, _::32, debug::binary>>} = frame
    # IO.inspect(debug)
  end
end
