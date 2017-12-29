defmodule Ace.HTTP2.Settings.MaxFrameSizeTest do
  use ExUnit.Case

  alias Ace.{HTTP.Service, HTTP2.Frame}

  test "service cannot be started with max_frame_size less than default value" do
    assert {:error, _} =
             Service.start_link({Raxx.Forwarder, %{target: self()}}, port: 0, max_frame_size: 16383)
  end

  test "service cannot be started with max_frame_size greater than default value" do
    assert {:error, _} =
             Service.start_link(
               {Raxx.Forwarder, %{target: self()}},
               port: 0,
               max_frame_size: 16_777_216
             )
  end

  test "max_frame_size setting is sent in handshake" do
    opts = [
      port: 0,
      certfile: Support.test_certfile(),
      keyfile: Support.test_keyfile(),
      max_frame_size: 20000
    ]

    assert {:ok, service} = Service.start_link({Raxx.Forwarder, %{target: self()}}, opts)
    {:ok, port} = Service.port(service)
    connection = Support.open_connection(port)
    assert {:ok, Frame.Settings.new(max_frame_size: 20000)} == Support.read_next(connection)
  end

  test "sending oversized frame is a connection error of type frame_size_error" do
    opts = [
      port: 0,
      certfile: Support.test_certfile(),
      keyfile: Support.test_keyfile(),
      max_frame_size: 20000
    ]

    assert {:ok, service} = Service.start_link({Raxx.Forwarder, %{target: self()}}, opts)
    {:ok, port} = Service.port(service)

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new())

    assert {:ok, Frame.Settings.new(max_frame_size: 20000)} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)
    :ok = Support.send_frame(connection, Frame.Settings.ack())

    bit_size = 20001 * 8
    frame = Frame.Data.new(1, <<0::size(bit_size)>>, false)

    :ok = Support.send_frame(connection, frame)

    assert {:ok, frame = %Frame.GoAway{}} = Support.read_next(connection)
    assert :frame_size_error = frame.error
    assert "Frame greater than max allowed: (20001 >= 20000)" = frame.debug
  end

  test "Service uses default setting until client has acknowledged" do
    opts = [
      port: 0,
      certfile: Support.test_certfile(),
      keyfile: Support.test_keyfile(),
      max_frame_size: 20000
    ]

    assert {:ok, service} = Service.start_link({Raxx.Forwarder, %{target: self()}}, opts)
    {:ok, port} = Service.port(service)

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new())

    assert {:ok, Frame.Settings.new(max_frame_size: 20000)} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)

    bit_size = 16385 * 8
    frame = Frame.Data.new(1, <<0::size(bit_size)>>, false)

    :ok = Support.send_frame(connection, frame)

    assert {:ok, frame = %Frame.GoAway{}} = Support.read_next(connection)
    assert :frame_size_error = frame.error
    assert "Frame greater than max allowed: (16385 >= 16384)" = frame.debug
  end

  # Settings on client

  # Call things waiting in stream blocks
  test "client cannot request max_frame_size less than default" do
    opts = [port: 0, certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({Raxx.Forwarder, %{target: self()}}, opts)
    {:ok, port} = Service.port(service)

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new(max_frame_size: 16383))
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)
    assert {:ok, %{error: :protocol_error, debug: message}} = Support.read_next(connection)
    assert "invalid value for max_frame_size setting" = message
  end

  @tag :skip
  test "large response blocks from server are broken into multiple data parts" do
    opts = [port: 0, certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({Raxx.Forwarder, %{target: self()}}, opts)
    {:ok, port} = Service.port(service)

    connection = Support.open_connection(port)

    :ok = :ssl.send(connection, Ace.HTTP2.Connection.preface())
    :ok = Support.send_frame(connection, Frame.Settings.new(max_frame_size: 17000))
    assert {:ok, Frame.Settings.new()} == Support.read_next(connection)
    assert {:ok, Frame.Settings.ack()} == Support.read_next(connection)

    encode_context = Ace.HPack.new_context(1000)
    headers = Support.home_page_headers()
    {:ok, {header_block, _encode_context}} = Ace.HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(1, header_block, true, true)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", from, {:headers, _received, state}}, 1000
    long_value = Enum.map(1..4000, fn _ -> "a" end) |> Enum.join("")

    response =
      Raxx.response(200)
      |> Raxx.set_header("foo1", long_value)
      |> Raxx.set_header("foo2", long_value)
      |> Raxx.set_header("foo3", long_value)
      |> Raxx.set_header("foo4", long_value)
      |> Raxx.set_header("foo5", long_value)
      |> Raxx.set_header("foo6", long_value)
      |> Raxx.set_header("foo7", long_value)
      |> Raxx.set_header("foo8", long_value)
      |> Raxx.set_header("foo9", long_value)
      |> Raxx.set_body(true)

    data = Raxx.data(Enum.map(1..10, fn _ -> long_value end) |> Enum.join(""))

    request =
      Raxx.request(:GET, "/bar")
      |> Raxx.set_header("bar1", long_value)
      |> Raxx.set_header("bar2", long_value)
      |> Raxx.set_header("bar3", long_value)
      |> Raxx.set_header("bar4", long_value)
      |> Raxx.set_header("bar5", long_value)
      |> Raxx.set_header("bar6", long_value)
      |> Raxx.set_header("bar7", long_value)
      |> Raxx.set_header("bar8", long_value)
      |> Raxx.set_header("bar9", long_value)

    GenServer.reply(from, {[response, {:promise, request}, data, Raxx.tail()], state})

    assert {:ok, frame = %Frame.Headers{end_headers: false}} = Support.read_next(connection)
    assert 17000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: false}} = Support.read_next(connection)
    assert 17000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: true}} = Support.read_next(connection)
    assert 17000 >= :erlang.iolist_size(frame.header_block_fragment)

    assert {:ok, frame = %Frame.PushPromise{end_headers: false}} = Support.read_next(connection)
    assert 17000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: false}} = Support.read_next(connection)
    assert 17000 == :erlang.iolist_size(frame.header_block_fragment)
    assert {:ok, frame = %Frame.Continuation{end_headers: true}} = Support.read_next(connection)
    assert 17000 >= :erlang.iolist_size(frame.header_block_fragment)

    assert {:ok, frame = %Frame.Data{end_stream: false}} = Support.read_next(connection)
    assert 17000 == :erlang.iolist_size(frame.data)
    assert {:ok, frame = %Frame.Data{end_stream: false}} = Support.read_next(connection)
    assert 17000 == :erlang.iolist_size(frame.data)
    assert {:ok, frame = %Frame.Data{end_stream: true}} = Support.read_next(connection)
    assert 17000 >= :erlang.iolist_size(frame.data)
  end
end
