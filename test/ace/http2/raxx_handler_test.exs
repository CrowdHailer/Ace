defmodule Ace.HTTP2.RaxxHandlerTest do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Frame
  }

  setup do
    {:ok, stream_supervisor} = Supervisor.start_link(
      [Supervisor.Spec.worker(Ace.HTTP2.Stream.RaxxHandler, [RaxxForwarder, self()], [restart: :temporary])],
      [strategy: :simple_one_for_one]
    )
    {_server, port} = Support.start_server(stream_supervisor)
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

  test "required headers are translated", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    headers = home_page_headers()
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", _from, request = %Raxx.Request{}}

    assert :https = request.scheme
    assert :GET = request.method
    assert "example.com" = request.host
    assert [] = request.path
  end

  # DEBT do we validate content-length? No firefox does not for responses
  test "data is added to body", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    headers = home_page_headers()
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, false)
    Support.send_frame(connection, headers_frame)

    data_frame = Frame.Data.new(1, "Hello, World!", true)
    Support.send_frame(connection, data_frame)

    assert_receive {:"$gen_call", _from, request = %Raxx.Request{}}
    assert "Hello, World!" = request.body
  end

  test "data from multiple frames is added to body", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    headers = home_page_headers()
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, false)
    Support.send_frame(connection, headers_frame)

    data_frame = Frame.Data.new(1, "Hello, ", false)
    Support.send_frame(connection, data_frame)

    data_frame = Frame.Data.new(1, "World!", true)
    Support.send_frame(connection, data_frame)

    assert_receive {:"$gen_call", _from, request = %Raxx.Request{}}
    assert "Hello, World!" = request.body
  end

  test "path data is processed", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    headers = [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/foo/bar?a=value&b[c]=nested%20value"}
    ]
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", _from, request = %Raxx.Request{}}
    assert ["foo", "bar"] = request.path
    assert %{"a" => "value", "b" => %{"c" => "nested value"}} = request.query
  end

  test "optional headers are added to request", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    headers = home_page_headers([{"content-length", "0"}, {"accept", "*/*"}])
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", _from, request = %Raxx.Request{}}
    assert [{"content-length", "0"}, {"accept", "*/*"}] = request.headers
  end

  test "multiple cookies are handled", %{client: connection} do

  end

  test "response status is set", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    decode_context = :hpack.new_context(1_000)
    headers = home_page_headers()
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", from, request = %Raxx.Request{}}
    GenServer.reply(from, {:ok, Raxx.Response.forbidden()})

    assert {:ok, %Frame.Headers{end_stream: true, header_block_fragment: header_block}} = Support.read_next(connection, 2_000)
    assert {:ok, {[{":status", "403"}], _decode_context}} = :hpack.decode(header_block, decode_context)
  end

  test "other headers are sent", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    decode_context = :hpack.new_context(1_000)
    headers = home_page_headers()
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", from, request = %Raxx.Request{}}
    GenServer.reply(from, {:ok, Raxx.Response.ok([{"server", "Ace"}])})

    assert {:ok, %Frame.Headers{end_stream: true, header_block_fragment: header_block}} = Support.read_next(connection, 2_000)
    assert {:ok, {[{":status", "200"}, {"server", "Ace"}], _decode_context}} = :hpack.decode(header_block, decode_context)

  end

  test "response body is sent", %{client: connection} do
    encode_context = :hpack.new_context(1_000)
    decode_context = :hpack.new_context(1_000)
    headers = home_page_headers()
    {:ok, {header_block, encode_context}} = :hpack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", from, request = %Raxx.Request{}}
    GenServer.reply(from, {:ok, Raxx.Response.ok("Hello, World!")})

    assert {:ok, %Frame.Headers{end_stream: false, header_block_fragment: header_block}} = Support.read_next(connection, 2_000)
    assert {:ok, {[{":status", "200"}], _decode_context}} = :hpack.decode(header_block, decode_context)
    assert {:ok, %Frame.Data{end_stream: true, data: "Hello, World!"}} = Support.read_next(connection, 2_000)
  end

  # should be a stream_test
  test "large response body sent in parts", %{client: connection} do

  end

  test "push promises are sent after headers", %{client: connection} do

  end

  defp home_page_headers(rest \\ []) do
    [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ] ++ rest
  end
end
