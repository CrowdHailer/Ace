defmodule Ace.HTTP2RoutingTest do
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

  # Sending without required header is an error
  test "sending unpadded headers", %{client: connection} do
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"},
      {"content-length", "0"}
    ]

    encode_context = :hpack.new_context(1_000)
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    <<hbf1::binary-size(8), hbf2::binary>> = header_block
    headers_frame = Frame.Headers.new(1, hbf1, false, true)
    continuation_frame = Frame.Continuation.new(1, hbf2, true)

    Support.send_frame(connection, headers_frame)
    Support.send_frame(connection, continuation_frame)

    assert_receive {:"$gen_call", from, {:start_child, []}}
    GenServer.reply(from, {:ok, self()})

    assert_receive {stream, _headers}
    headers = %{
      ":status" => "200",
      "content-length" => "13"
    }
    preface = %{
      headers: headers,
      end_stream: false
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
    data = %{
      data: "Hello, World!",
      end_stream: true
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, data)
    # TODO test 200 response
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    decode_context = :hpack.new_context(1_000)
    :hpack.decode(hbf, decode_context)
    |> IO.inspect
    assert {:ok, %{data: "Hello, World!"}} = Support.read_next(connection, 2_000)
  end

  test "sending padded headers", %{client: connection} do
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"},
      {"content-length", "0"}
    ]

    encode_context = :hpack.new_context(1_000)
    {:ok, {header_block_fragment, encode_context}} = :hpack.encode(headers, encode_context)

    payload = Frame.pad_data(header_block_fragment, 2)

    size = :erlang.iolist_size(payload)

    flags = <<0::4, 1::1, 1::1, 0::1, 1::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, payload::binary>>)
    assert_receive {:"$gen_call", from, {:start_child, []}}
    GenServer.reply(from, {:ok, self()})

    assert_receive {stream, _headers}
    headers = %{
      ":status" => "200",
      "content-length" => "13"
    }
    preface = %{
      headers: headers,
      end_stream: false
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
    data = %{
      data: "Hello, World!",
      end_stream: true
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, data)
    # TODO test 200 response header
    assert {:ok, %{header_block_fragment: _hbf}} = Support.read_next(connection, 2_000)
    assert {:ok, %{data: "Hello, World!"}} = Support.read_next(connection, 2_000)
  end

  test "send post with data", %{client: connection} do

    encode_context = :hpack.new_context(1_000)
    decode_context = :hpack.new_context(1_000)
    {:ok, {body, encode_context}} = :hpack.encode([{":method", "POST"}, {":scheme", "https"}, {":path", "/"}, {":authority", "example.com"}], encode_context)

    size = :erlang.iolist_size(body)

    # <<_, _, priority, _, padded, end_headers, _, end_stream>>
    flags = <<0::5, 1::1, 0::1, 0::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    data_frame = Frame.Data.new(1, "Upload", true) |> Frame.Data.serialize()
    :ssl.send(connection, data_frame)

    assert_receive {:"$gen_call", from, {:start_child, []}}
    GenServer.reply(from, {:ok, self()})

    assert_receive {stream, _headers}
    assert_receive {stream, _data}
    headers = %{
      ":status" => "201",
      "content-length" => "0"
    }
    preface = %{
      headers: headers,
      end_stream: false
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)

    assert {:ok, %{stream_id: 0, increment: 65_535}} = Support.read_next(connection, 2_000)
    assert {:ok, %{stream_id: _, increment: 65_535}} = Support.read_next(connection, 2_000)
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    assert {:ok, {[{":status", "201"}, {"content-length", "0"}], _decode_context}} = :hpack.decode(hbf, decode_context)
  end

  @tag :skip
  test "send post with padded data", %{client: connection} do

    decode_context = :hpack.new_context(1_000)
    encode_context = :hpack.new_context(1_000)
    {:ok, {body, encode_context}} = :hpack.encode([{":method", "POST"}, {":scheme", "https"}, {":path", "/"}], encode_context)

    size = :erlang.iolist_size(body)

    # <<_, _, priority, _, padded, end_headers, _, end_stream>>
    flags = <<0::5, 1::1, 0::1, 0::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    data_frame = Frame.Data.new(1, "Upload", pad_length: 2, end_stream: true)
    :ssl.send(connection, data_frame)
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    assert {:ok, {[{":status", "201"}, {"content-length", "0"}], _decode_context}} = :hpack.decode(hbf, decode_context)
  end
end
