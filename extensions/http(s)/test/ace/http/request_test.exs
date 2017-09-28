defmodule Ace.HTTP.RequestTest do
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

  test "header information is added to request", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    x-test: Value

    """
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.scheme == :http
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == %{"var" => "1"}
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "Header keys in request are cast to lowercase", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    Host: example.com:1234
    X-test: Value

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.scheme == :http
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == %{"var" => "1"}
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "handles request with split start-line ", %{port: port} do
    part_1 = "GET /foo/bar?var"
    part_2 = """
    =1 HTTP/1.1
    host: example.com:1234
    x-test: Value

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, part_1)
    :ok = Process.sleep(100)
    :ok = :gen_tcp.send(socket, part_2)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.scheme == :http
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == %{"var" => "1"}
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "handles request with split headers ", %{port: port} do
    part_1 = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    """
    part_2 = """
    x-test: Value

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, part_1)
    :ok = Process.sleep(100)
    :ok = :gen_tcp.send(socket, part_2)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.scheme == :http
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == %{"var" => "1"}
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "request with content-length 0 has no body", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    content-length: 0

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.body == false
  end

  test "request stream will end when all content has been read", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    content-length: 14

    Hello, World!
    And a bunch more content
    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.body == true

    assert_receive {:"$gen_call", from, {:fragment, fragment, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert "Hello, World!\n" == fragment

    assert_receive {:"$gen_call", from, {:trailers, [], state}}, 1_000
    GenServer.reply(from, {[], state})
  end

  test "application will be invoked as content is received", %{port: port} do
    request_head = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    content-length: 14

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, request_head)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert request.body == true

    :ok = :gen_tcp.send(socket, "Hello, ")
    Process.sleep(100)
    :ok = :gen_tcp.send(socket, "World!\n")

    assert_receive {:"$gen_call", from, {:fragment, "Hello, ", state}}, 1_000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:fragment, "World!\n", state}}, 1_000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:trailers, [], state}}, 1_000
    GenServer.reply(from, {[], state})
  end
end
