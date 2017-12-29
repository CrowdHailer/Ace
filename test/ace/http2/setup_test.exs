defmodule Ace.HTTP2SetupTest do
  use ExUnit.Case

  setup do
    {:ok, service} =
      Ace.HTTP.Service.start_link(
        {Raxx.Forwarder, %{target: self()}},
        port: 0,
        certfile: Support.test_certfile(),
        keyfile: Support.test_keyfile()
      )

    {:ok, port} = Ace.HTTP.Service.port(service)
    connection = Support.open_connection(port)
    {:ok, %{client: connection}}
  end

  alias Ace.HTTP2.{Frame}

  # DEBT move to h2spec
  test "client must first send settings frame", %{client: connection} do
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)

    payload = [
      Ace.HTTP2.Connection.preface(),
      Frame.Ping.new(<<0::64>>) |> Frame.Ping.serialize()
    ]

    :ssl.send(connection, payload)
    assert {:ok, %Frame.GoAway{debug: _}} = Support.read_next(connection)
  end

  # DEBT move to h2spec
  test "empty settings are acked", %{client: connection} do
    payload = [
      Ace.HTTP2.Connection.preface(),
      Frame.Settings.new() |> Frame.Settings.serialize()
    ]

    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
  end
end
