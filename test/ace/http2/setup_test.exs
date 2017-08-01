defmodule Ace.HTTP2SetupTest do
  use ExUnit.Case

  setup do
    {_server, port} = Support.start_server({__MODULE__, %{test_pid: self()}})
    connection = Support.open_connection(port)
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
      Ace.HTTP2.Connection.preface(),
      Frame.Ping.new(<<0::64>>) |> Frame.Ping.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Frame.GoAway{debug: _}} = Support.read_next(connection)
  end

  test "empty settings are acked", %{client: connection} do
    payload = [
      Ace.HTTP2.Connection.preface(),
      Frame.Settings.new() |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
  end

  test "sending settings", %{client: connection} do
    payload = [
      Ace.HTTP2.Connection.preface(),
      Frame.Settings.new(header_table_size: 200) |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
  end
end
