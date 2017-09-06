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
    host: www.raxx.com
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
    Host: www.raxx.com
    X-test: Value

    """

    # Should have exactly the same asserts as above
  end

  test "handles request with split start-line ", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: www.raxx.com
    x-test: Value

    """

    # Send over socket in two chunks with break in first line
  end

  test "handles request with split headers ", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: www.raxx.com
    x-test: Value

    """

    # Send over socket in two chunks with break in headers
  end

  test "request stream will end when length of content has been read" do
    # Send request with content length
    # assert_receive head with body true
    # Send part of body
    # assert_receive fragment with endstream false
    # Send rest of body
    # assert_receive fragment with endstream true
  end

  test "truncates body to required length ", %{port: port} do
    # Send request with content length
    # assert_receive head with body true
    # Send part of body
    # assert_receive fragment with endstream false
    # Send rest of body and start of next request
    # assert_receive fragment with only content and none of next request
  end

  @tag :skip
  test "will handle two requests over the same connection", %{port: port} do
    # DEBT leave pipelining as rarely used in by modern browsers
  end

  @tag :skip
  test "can send response even when request headers are sent, content-length is non-zero but entire body is not sent", %{port: port} do
  end
end
