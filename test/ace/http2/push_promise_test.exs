defmodule Ace.HTTP2.PushPromiseTest do
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

  test "sending a push promise from a client is a protocol error", %{client: connection} do
    priority_frame = Frame.PushPromise.new(2, 1, "header_block_fragment", true)
    |> IO.inspect
    :ssl.send(connection, Frame.PushPromise.serialize(priority_frame) |> IO.inspect)
    assert {:ok, %Frame.GoAway{debug: debug}} = Support.read_next(connection, 2_000)
    assert "Clients cannot send push promises" = debug
  end



end
