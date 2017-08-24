defmodule Ace.HTTP2.Settings.MaxFrameSizeTest do
  use ExUnit.Case

  alias Ace.{
    Request,
    Response,
    HTTP2.Client,
    HTTP2.Service,
    HTTP2.Server,
    HTTP2.Frame
  }

  test "service cannot be started with max_frame_size less than default value" do
    assert {:error, _} = Service.start_link({ForwardTo, [self()]}, port: 0, max_frame_size: 16_383)
  end

  test "service cannot be started with max_frame_size greater than default value" do
    assert {:error, _} = Service.start_link({ForwardTo, [self()]}, port: 0, max_frame_size: 16_777_216)
  end

  test "max_frame_size setting is sent in handshake" do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile(), max_frame_size: 20_000]
    assert {:ok, service} = Service.start_link({ForwardTo, [self()]}, opts)
    assert_receive {:listening, ^service, port}
    connection = Support.open_connection(port)
    assert {:ok, Frame.Settings.new(max_frame_size: 20_000)} == Support.read_next(connection)
  end

  test "sending oversized frame is a connection error of type frame_size_error" do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile(), max_frame_size: 20_000]
    assert {:ok, service} = Service.start_link({ForwardTo, [self()]}, opts)
    assert_receive {:listening, ^service, port}

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new())

    assert {:ok, Frame.Settings.new(max_frame_size: 20_000)} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
    :ok = Support.send_frame(connection, Frame.Settings.ack())

    bit_size = 20_001 * 8
    frame = Frame.Data.new(1, <<0::size(bit_size)>>, false)

    :ok = Support.send_frame(connection, frame)

    assert {:ok, frame = %Frame.GoAway{}} = Support.read_next(connection)
    assert :frame_size_error = frame.error
    assert "Frame greater than max allowed: (20001 >= 20000)" = frame.debug
  end

  test "Service uses default setting until client has acknowledged" do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile(), max_frame_size: 20_000]
    assert {:ok, service} = Service.start_link({ForwardTo, [self()]}, opts)
    assert_receive {:listening, ^service, port}

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new())

    assert {:ok, Frame.Settings.new(max_frame_size: 20_000)} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)

    bit_size = 16_385 * 8
    frame = Frame.Data.new(1, <<0::size(bit_size)>>, false)

    :ok = Support.send_frame(connection, frame)

    assert {:ok, frame = %Frame.GoAway{}} = Support.read_next(connection)
    assert :frame_size_error = frame.error
    assert "Frame greater than max allowed: (16385 >= 16384)" = frame.debug
  end

  # Settings on client

  # Call things waiting in stream blocks
  test "client cannot request max_frame_size less than default" do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({ForwardTo, [self()]}, opts)
    assert_receive {:listening, ^service, port}

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new(max_frame_size: 16_383))
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)
    assert {:ok, %{error: protocol_error, debug: message}} = Support.read_next(connection)
    assert "invalid value for max_frame_size setting" = message
  end

  test "large response blocks from server are broken into multiple fragments" do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({ForwardTo, [self()]}, opts)
    assert_receive {:listening, ^service, port}

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new(max_frame_size: 17_000))
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)

    encode_context = Ace.HPack.new_context(1_000)
    headers = Support.home_page_headers()
    {:ok, {header_block, _encode_context}} = Ace.HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {server_stream, %Request{}}, 1_000
    long_value = Enum.map(1..4_000, fn(_) -> "a" end) |> Enum.join("")
    response = Response.new(200, [
      {"foo1", long_value},
      {"foo2", long_value},
      {"foo3", long_value},
      {"foo4", long_value},
      {"foo5", long_value},
      {"foo6", long_value},
      {"foo7", long_value},
      {"foo8", long_value},
      {"foo9", long_value},
    ], true)
    Server.send_response(server_stream, response)

    assert {:ok, frame = %Frame.Headers{end_headers: false}} = Support.read_next(connection)
    assert 17_000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: false}} = Support.read_next(connection)
    assert 17_000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: true}} = Support.read_next(connection)
    assert 17_000 >= :erlang.iolist_size(frame.header_block_fragment)

    Server.send_data(server_stream, Enum.map(1..10, fn(_) -> long_value end) |> Enum.join(""), true)
    assert {:ok, frame = %Frame.Data{end_stream: false}} = Support.read_next(connection)
    assert 17_000 == :erlang.iolist_size(frame.data)
    assert {:ok, frame = %Frame.Data{end_stream: false}} = Support.read_next(connection)
    assert 17_000 == :erlang.iolist_size(frame.data)
    assert {:ok, frame = %Frame.Data{end_stream: true}} = Support.read_next(connection)
    assert 17_000 >= :erlang.iolist_size(frame.data)

    request = Request.get("/bar", [
      {"bar1", long_value},
      {"bar2", long_value},
      {"bar3", long_value},
      {"bar4", long_value},
      {"bar5", long_value},
      {"bar6", long_value},
      {"bar7", long_value},
      {"bar8", long_value},
      {"bar9", long_value},
    ])
    Server.send_promise(server_stream, request)
    assert {:ok, frame = %Frame.PushPromise{end_headers: false}} = Support.read_next(connection)
    assert 17_000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: false}} = Support.read_next(connection)
    assert 17_000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: true}} = Support.read_next(connection)
    assert 17_000 >= :erlang.iolist_size(frame.header_block_fragment)
  end
end
