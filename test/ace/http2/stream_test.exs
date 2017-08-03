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

  test "client cannot send on stream 0", %{client: connection} do
    encode_context = HPack.new_context(1_000)
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ]
    {:ok, {header_block, encode_context}} = HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(2, header_block, true, true)
    Support.send_frame(connection, headers_frame)
    assert {:ok, %Frame.GoAway{debug: message}} = Support.read_next(connection, 2_000)
    assert "Clients must start odd streams" = message
    # assert {:ok, %Frame.RstStream{error: :stream_closed, stream_id: 1}} = Support.read_next(connection, 2_000)
  end

  test "client must start odd numbered streams", %{client: connection} do
    encode_context = HPack.new_context(1_000)
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ]
    {:ok, {header_block, encode_context}} = HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(2, header_block, true, true)
    Support.send_frame(connection, headers_frame)
    assert {:ok, %Frame.GoAway{debug: message}} = Support.read_next(connection, 2_000)
    assert "Clients must start odd streams" = message
  end

  test "cannot send more headers after frame with end stream", %{client: connection} do
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

    assert_receive {:"$gen_call", from, {:start_child, []}}
    GenServer.reply(from, {:ok, self()})

    Support.send_frame(connection, headers_frame)
    assert {:ok, %Frame.GoAway{error: :stream_closed}} = Support.read_next(connection, 2_000)
  end

  test "cannot send data after frame with end stream", %{client: connection} do
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

    assert_receive {:"$gen_call", from, {:start_child, []}}
    GenServer.reply(from, {:ok, self()})

    data_frame = Frame.Data.new(1, "hi", true)
    Support.send_frame(connection, data_frame)
    assert {:ok, %Frame.GoAway{error: :stream_closed}} = Support.read_next(connection, 2_000)
  end

  test "cannot start a stream with data frame", %{client: connection} do
    data_frame = Frame.Data.new(1, "hi", true)
    Support.send_frame(connection, data_frame)

    assert_receive {:"$gen_call", from, {:start_child, []}}
    GenServer.reply(from, {:ok, self()})

    assert {:ok, %Frame.GoAway{debug: message}} = Support.read_next(connection, 2_000)
    assert "DATA frame received on a stream in idle state. (RFC7540 5.1)" = message
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
