defmodule Ace.HTTP2.StreamTest do
  use ExUnit.Case

  alias Ace.{
    HPack
  }
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

  test "stream is reset if worker terminates", %{client: connection} do
    encode_context = HPack.new_context(1_000)
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ]
    {:ok, {header_block, encode_context}} = HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)
    receive do
      {:"$gen_call", from, {:start_child, []}} ->
        GenServer.reply(from, {:ok, spawn(fn() -> Process.sleep(1_000) end)})
    end

    assert {:ok, %Frame.RstStream{error: :internal_error, stream_id: 1}} = Support.read_next(connection, 2_000)
  end
end
