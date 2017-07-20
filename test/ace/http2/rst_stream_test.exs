defmodule Ace.HTTP2.RstStreamTest do
  use ExUnit.Case

  setup do
    {_server, port} = Support.start_server(self())
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

  test "rst_stream frame is logged", %{client: connection} do
    rst_stream_frame = Frame.RstStream.new(21, :internal_error)
    :ssl.send(connection, Frame.RstStream.serialize(rst_stream_frame) |> IO.inspect)
    assert {:error, :timeout} = Support.read_next(connection, 2_000)
  end

  # send incorrectly sized rst_stream frame


end
