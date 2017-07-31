defmodule Ace.HTTP2ClientSettingsTest do
  use ExUnit.Case

  alias Ace.HTTP2.Frame

  setup do
    {_server, port} = Support.start_server({__MODULE__, %{test_pid: self()}})
    connection = Support.open_connection(port)
    payload = [
      Ace.HTTP2.Connection.preface(),
      Ace.HTTP2.Frame.Settings.new() |> Ace.HTTP2.Frame.Settings.serialize(),
    ]
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
    assert "invalid value for max_frame_size setting" = message
  end
end
