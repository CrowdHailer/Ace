defmodule Ace.HTTP2Test do
  use ExUnit.Case

  alias Ace.{
    Request,
    Response,
    HTTP2.Client,
    HTTP2.Server
  }

  setup do
    # DEBT change to standard server start
    {_server, port} = Support.start_server(self())
    {:ok, %{port: port}}
  end

  test "request can be streamed from client to server", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.post("/", [{"content-type", "text/plain"}], true)
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, received = %Request{}}, 1_000
    assert received.path == request.path

    :ok = Client.send_data(client_stream, "Hello, ")
    assert_receive {^server_stream, %{data: "Hello, ", end_stream: false}}, 1_000

    :ok = Client.send_trailers(client_stream, [{"x-foo", "bar"}])
    assert_receive {^server_stream, %{headers: [{"x-foo", "bar"}], end_stream: true}}, 1_000
  end

  test "complete request with no body can be sent to server", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [{"content-type", "text/plain"}])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {_server_stream, received = %Request{}}, 1_000
    assert received.headers == request.headers
    assert received.path == "/"
    assert received.body == false
  end

  test "complete request with body can be sent to server", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.post("/", [{"content-type", "text/plain"}], "This is all the content.")
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, received = %Request{}}, 1_000
    assert received.headers == request.headers
    assert received.path == "/"
    assert received.body == true

    assert_receive {^server_stream, %{data: data, end_stream: true}}, 1_000
    assert request.body == data
  end

  # Client should not break protocol
  # disallow sending on an ended stream
  # disallow sending trailers which do not end stream

  test "response can be streamed from server to client", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [{"content-type", "text/plain"}])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, %Request{}}, 1_000

    response = Response.new(200, [{"content-type", "text/plain"}], true)
    Server.send_response(server_stream, response)

    assert_receive {^client_stream, received = %Response{}}, 1_000
    assert 200 == received.status

    Server.send_data(server_stream, "For the client")
    assert_receive {^client_stream, %{data: "For the client", end_stream: false}}, 1_000

    :ok = Client.send_trailers(server_stream, [{"x-foo", "bar"}])

    assert_receive {^client_stream, %{headers: [{"x-foo", "bar"}], end_stream: true}}, 1_000
  end

  test "complete response with no body can be sent to client", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [{"content-type", "text/plain"}])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, %Request{}}, 1_000

    response = Response.new(304, [], false)
    Server.send_response(server_stream, response)

    assert_receive {^client_stream, received = %Response{}}, 1_000
    assert received.status == 304
    assert received.body == false
  end

  test "complete response with body can be sent to client", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [{"content-type", "text/plain"}])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, %Request{}}, 1_000

    response = Response.new(200, [], "Here is all the bodies")
    Server.send_response(server_stream, response)

    assert_receive {^client_stream, received = %Response{}}, 1_000
    assert received.status == 200

    assert_receive {^client_stream, %{data: body}}, 1_000
    assert body == "Here is all the bodies"
  end

  # Check sending complete request ends stream with/out body

  test "send a promise from the server", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [{"content-type", "text/plain"}])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    request = %{Request.get("/favicon") | authority: "localhost"}
    assert_receive {server_stream, %Request{}}, 1_000
    Server.send_promise(server_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_pushed_stream, %Request{path: "/favicon"}}, 1_000
    IO.inspect(server_pushed_stream)

    assert_receive {^client_stream, {:promise, {client_promised_stream, %Request{path: "/favicon"}}}}, 1_000
    IO.inspect(client_promised_stream)

    response = Response.new(200, [{"content-type", "text/html"}], true)
    Server.send_response(server_pushed_stream, response)

    assert_receive {^client_promised_stream, %Response{headers: [{"content-type", "text/html"}]}}, 1_000
  end

  # Server can push on closed, idle streams
  # Test cannot push to client with push disabled
end
