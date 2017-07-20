defmodule Ace.HTTP2PingTest do
  use ExUnit.Case

  setup do
    {_server, port} = Support.start_server({__MODULE__, %{test_pid: self()}})
    connection = Support.open_connection(port)
    payload = [
      Ace.HTTP2.Connection.preface(),
      Ace.HTTP2.Frame.Settings.new() |> Ace.HTTP2.Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: true}} == Support.read_next(connection)
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
    assert {:ok, %Frame.Ping{ack: true, identifier: identifier}} == Support.read_next(connection)
  end

  test "incorrect ping frame is a connection error", %{client: connection} do
    malformed_frame = %Frame.Ping{identifier: <<1_000::80>>, ack: false}
    :ssl.send(connection, Frame.Ping.serialize(malformed_frame))
    
    # TODO check that last stream id is correct
    assert {:ok, frame = %Frame.GoAway{}} = Support.read_next(connection)
    assert "Ping identifier must be 64 bits" == frame.debug
    assert :frame_size_error == frame.error
  end

  # send acked ping
  # send bad ping expecting stream_id > 0

end
