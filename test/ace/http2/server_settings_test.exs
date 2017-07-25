defmodule Ace.HTTP2.ServerSettingsTest do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Frame
  }

  setup do
    {_server, port} = Support.start_server(self())
    connection = Support.open_connection(port)
    payload = [
      Ace.HTTP2.Connection.preface(),
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
    assert "Frame greater than max allowed: (16385 >= 16384)" = frame.debug
    assert :frame_size_error = frame.error
  end

  # send incorrectly sized rst_stream frame


end
