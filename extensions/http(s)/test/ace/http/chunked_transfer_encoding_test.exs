defmodule Ace.HTTP.ChunkedTransferEncodingTest do
  use ExUnit.Case

  import ExUnit.CaptureLog, only: [capture_log: 1]

  setup do
    raxx_app = {Raxx.Forwarder, %{test: self()}}
    capture_log fn() ->
      {:ok, endpoint} = Ace.HTTP.start_link(raxx_app, port: 0)
      {:ok, port} = Ace.HTTP.port(endpoint)
      send(self(), {:port, port})
    end
    port = receive do
      {:port, port} -> port
    end
    {:ok, %{port: port}}
  end

  test "request can be sent in chunks", %{port: port} do
    request_head = """
    POST / HTTP/1.1
    host: example.com
    x-test: Value
    transfer-encoding: chunked

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, request_head)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    state = Map.put(state, :count, 1)
    GenServer.reply(from, {[], state})

    assert request.headers == [{"x-test", "Value"}]

    :ok = :gen_tcp.send(socket, "D\r\nHello,")
    Process.sleep(100)
    :ok = :gen_tcp.send(socket, " World!\r\nD")

    assert_receive {:"$gen_call", from, {:fragment, fragment, state}}, 1_000
    assert 1 == state.count
    assert fragment == "Hello, World!"

    state = Map.put(state, :count, 2)
    GenServer.reply(from, {[], state})

    :ok = :gen_tcp.send(socket, "\r\nHello, World!\r\n")

    assert_receive {:"$gen_call", from, {:fragment, fragment, state}}, 1_000
    assert 2 == state.count
    assert fragment == "Hello, World!"

    state = Map.put(state, :count, 3)
    GenServer.reply(from, {[], state})

    :ok = :gen_tcp.send(socket, "0\r\n\r\n")
    assert_receive {:"$gen_call", _from, {:trailers, [], state}}, 1_000
    assert 3 == state.count
  end

  @tag :skip
  test "cannot receive content-length with transfer-encoding" do

  end

  @tag :skip
  test "cannot handle any other transfer-encoding" do

  end

  test "response without content length will be sent chunked", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, state}}, 1_000
    response = Raxx.response(:ok)
    |> Raxx.set_header("x-test", "Value")
    |> Raxx.set_body(true)
    state = Map.put(state, :count, 1)

    GenServer.reply(from, {[response], state})

    assert_receive {:tcp, ^socket, headers}, 1_000
    assert headers == "HTTP/1.1 200 OK\r\nconnection: close\r\ntransfer-encoding: chunked\r\nx-test: Value\r\n\r\n"

    {server, _ref} = from
    send(server, {[Raxx.fragment("Hello, ")], state})

    assert_receive {:tcp, ^socket, part}, 1_000
    assert part == "7\r\nHello, \r\n"

    send(server, {[Raxx.fragment("World!", true)], state})

    assert_receive {:tcp, ^socket, part}, 1_000
    assert part == "6\r\nWorld!\r\n0\r\n\r\n"

    assert_receive {:tcp_closed, ^socket}
  end
  # DEBT try sending empty fragment with end_stream false? should not end stream
end
