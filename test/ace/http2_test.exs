defmodule Ace.HTTP2Test do
  use ExUnit.Case

  alias Raxx.{Request, Response}
  alias Ace.HTTP2.Client

  setup do
    opts = [
      port: 0,
      owner: self(),
      certfile: Support.test_certfile(),
      keyfile: Support.test_keyfile()
    ]

    assert {:ok, service} = Ace.HTTP.Service.start_link({Raxx.Forwarder, %{target: self()}}, opts)
    {:ok, port} = Ace.HTTP.Service.port(service)
    {:ok, %{port: port}}
  end

  test "exits normal when client closes connection", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from = {worker, _ref}, {:headers, _received, state}}, 1000
    GenServer.reply(from, {[], state})
    monitor = Process.monitor(worker)

    :ok = Client.stop(client)

    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1000
  end

  # Request

  test "header information sent to server is availale on request", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request =
      Raxx.request(:GET, "https://example.com:1234/foo/bar?var=1")
      |> Raxx.set_header("content-type", "text/plain")

    :ok = Ace.HTTP2.send(client_stream, request)
    assert_receive {:"$gen_call", from, {:headers, received, state}}, 1000
    GenServer.reply(from, {[], state})

    assert received.scheme == :https
    assert received.authority == "example.com:1234"
    assert received.method == :GET
    assert received.mount == []
    assert received.path == ["foo", "bar"]
    assert received.raw_path == "/foo/bar"
    assert received.query == "var=1"
    assert received.headers == request.headers
    assert received.body == false
  end

  test "request stream will end with trailers", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request =
      Raxx.request(:POST, "/")
      |> Raxx.set_header("content-type", "text/plain")
      |> Raxx.set_body(true)

    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, received, state}}, 1000
    GenServer.reply(from, {[], state})
    assert received.path == request.path

    data = Raxx.data("Hello, ")
    :ok = Ace.HTTP2.send(client_stream, data)
    assert_receive {:"$gen_call", from, {:data, "Hello, ", state}}, 1000
    GenServer.reply(from, {[], state})

    data = Raxx.data([[], "World", "!"])
    :ok = Ace.HTTP2.send(client_stream, data)
    assert_receive {:"$gen_call", from, {:data, "World!", state}}, 1000
    GenServer.reply(from, {[], state})

    tail = Raxx.tail([{"x-foo", "bar"}])
    :ok = Ace.HTTP2.send(client_stream, tail)
    assert_receive {:"$gen_call", from, {:tail, [{"x-foo", "bar"}], state}}, 1000
    GenServer.reply(from, {[], state})
  end

  test "request stream ends for complete body, binary", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request =
      Raxx.request(:POST, "/")
      |> Raxx.set_header("content-type", "text/plain")
      |> Raxx.set_body("This is all the content.")

    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, _received, state}}, 1000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:data, "This is all the content.", state}}, 1000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:tail, [], state}}, 1000
    GenServer.reply(from, {[], state})
  end

  test "request stream ends for complete body, iolist", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request =
      Raxx.request(:POST, "/")
      |> Raxx.set_header("content-type", "text/plain")
      |> Raxx.set_body([["This"], " is all the content."])

    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, _received, state}}, 1000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:data, "This is all the content.", state}}, 1000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:tail, [], state}}, 1000
    GenServer.reply(from, {[], state})
  end

  # Response

  test "header information from server is added to response", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, %Request{}, _state}}, 1000

    response =
      Raxx.response(:no_content)
      |> Raxx.set_header("content-length", "0")

    GenServer.reply(from, response)

    assert_receive {^client_stream, received = %Response{}}, 1000
    assert received.status == 204
    assert received.headers == [{"content-length", "0"}]
    assert received.body == false
  end

  test "response stream ends when complete response is sent", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from = {worker, _ref}, {:headers, %Request{}, _state}}, 1000
    monitor = Process.monitor(worker)

    response =
      Raxx.response(200)
      |> Raxx.set_body("Here is all the bodies")

    GenServer.reply(from, response)

    assert_receive {^client_stream, %Response{}}, 1000

    assert_receive {^client_stream, %Raxx.Data{data: body}}, 1000
    assert body == "Here is all the bodies"
    assert_receive {^client_stream, %Raxx.Tail{headers: []}}, 1000

    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
  end

  test "response ends when trailers are send", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request =
      Raxx.request(:GET, "/")
      |> Raxx.set_header("content-type", "text/plain")

    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from = {worker, _ref}, {:headers, %Request{}, state}}, 1000
    monitor = Process.monitor(worker)

    reply = [
      Raxx.response(200) |> Raxx.set_header("content-type", "text/plain") |> Raxx.set_body(true),
      Raxx.data("For the client"),
      Raxx.tail([{"x-foo", "bar"}])
    ]

    GenServer.reply(from, {reply, state})

    assert_receive {^client_stream, %Response{}}, 1000

    assert_receive {^client_stream, %{data: "For the client"}}, 1000

    assert_receive {^client_stream, %Raxx.Tail{headers: [{"x-foo", "bar"}]}}, 1000

    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
  end

  test "send a promise from the server", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, %Request{}, state}}, 1000

    request = %{Raxx.request(:GET, "/favicon") | authority: "localhost"}

    reply = [
      Raxx.response(200) |> Raxx.set_body(true),
      {:promise, %{request | scheme: :https}}
    ]

    GenServer.reply(from, {reply, state})

    assert_receive {
                     ^client_stream,
                     {:promise, {client_promised_stream, %Request{path: ["favicon"]}}}
                   },
                   1000

    assert_receive {:"$gen_call", from, {:headers, %Request{path: ["favicon"]}, state}}, 1000

    response =
      Raxx.response(200)
      |> Raxx.set_header("content-type", "text/html")
      |> Raxx.set_body(true)

    GenServer.reply(from, {[response], state})

    assert_receive {^client_promised_stream, %Response{headers: [{"content-type", "text/html"}]}},
                   1000
  end

  test "promise is dropped when push disabled", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port}, enable_push: false)
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, %Request{}, state}}, 1000

    request = %{Raxx.request(:GET, "/favicon") | authority: "localhost"}

    reply = [
      Raxx.response(200) |> Raxx.set_body(true),
      {:promise, request}
    ]

    GenServer.reply(from, {reply, state})

    refute_receive {
                     ^client_stream,
                     {:promise, {_client_promised_stream, %Request{path: ["favicon"]}}}
                   },
                   1000

    refute_receive {:"$gen_call", _from, {:headers, %Request{path: ["favicon"]}, _state}}, 1000
  end

  ## Errors

  test "stream is reset if worker exits", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", {pid, _}, {:headers, %Request{}, _state}}, 1000
    Process.exit(pid, :abnormal)

    assert_receive {^client_stream, {:reset, :internal_error}}, 1000
  end

  @tag :skip
  test "Lost connection is forwarded to the worker", %{port: port} do
    Process.flag(:trap_exit, true)
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Raxx.request(:GET, "/")
    :ok = Ace.HTTP2.send(client_stream, request)

    assert_receive {:"$gen_call", from = {pid, _ref}, {:headers, _request, state}}, 1000

    response =
      Raxx.response(200)
      |> Raxx.set_body(true)

    _ref = Process.monitor(pid)
    GenServer.reply(from, {[response], state})

    Process.exit(client, :normal)

    assert_receive 5, 5000
  end
end
