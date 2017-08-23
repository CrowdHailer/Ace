defmodule Ace.HTTP2.StreamTest do
  use ExUnit.Case

  alias Ace.{
    HPack
  }
  alias Ace.HTTP2.{
    Frame
  }

  setup do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({__MODULE__, [1000]}, opts)
    assert_receive {:listening, ^service, port}
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

  def start_link(timeout) do
    {:ok, spawn(fn() -> Process.sleep(timeout) end)}
  end

  test "stream is reset if worker terminates", %{client: connection} do
    encode_context = HPack.new_context(1_000)
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ]
    {:ok, {header_block, _encode_context}} = HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert {:ok, %Frame.RstStream{error: :internal_error, stream_id: 1}} = Support.read_next(connection, 2_000)
  end
end
