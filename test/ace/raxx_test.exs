defmodule Raxx.Forwarder do
  use Raxx.Server

  def handle_headers(request, state = %{test: pid}) do
    GenServer.call(pid, {:headers, request, state})
  end
  def handle_fragment(data, state = %{test: pid}) do
    GenServer.call(pid, {:fragment, data, state})
  end
  def handle_trailers(trailers, state = %{test: pid}) do
    GenServer.call(pid, {:trailers, trailers, state})
  end
end

defmodule Ace.RaxxTest do
  use ExUnit.Case

  alias Ace.{
    Request,
    Response,
    HTTP2.Client,
    HTTP2.Server,
    HTTP2.Service,
  }

  setup do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({Ace.HTTP2.Worker, [{Raxx.Forwarder, %{test: self()}}]}, opts)
    assert_receive {:listening, ^service, port}
    {:ok, %{port: port}}
  end

  ### REQUEST

  test "query is forwarded", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/foo/bar?foo=1&bar=2", [])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", _from, {:headers, request, state}}, 1_000
    assert request.path == ["foo", "bar"]
    assert request.query == %{"bar" => "2", "foo" => "1"}
  end

  test "data is streamed", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.post("/", [], "All my data")
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, _request, state}}, 1_000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:fragment, data, state}}, 1_000
    GenServer.reply(from, {[], state})
    assert data == "All my data"

    assert_receive {:"$gen_call", from, {:trailers, [], state}}, 1_000
    response = Raxx.Response.new(:no_content, [], "")
    GenServer.reply(from, response)

    assert_receive {^client_stream, response = %Response{}}, 1_000
  end

  ## RESPONSE

  test "response information is sent", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [])
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1_000
    assert request.path == []

    body = "Hello, World!"
    response = Raxx.Response.ok(body, [])
    GenServer.reply(from, response)

    assert_receive {^client_stream, response = %Response{}}, 1_000
    assert response.status == 200
    assert response.headers == []
    assert_receive {^client_stream, %{data: ^body, end_stream: true}}, 1_000
  end

  ## Errors

  @tag :skip
  test "Lost connection is forwarded to the worker", %{port: port} do
    Process.flag(:trap_exit, true)
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.post("/", [], true)
    :ok = Client.send_request(client_stream, request)

    assert_receive {:"$gen_call", from = {pid, _ref}, {:headers, request, state}}, 1_000
    ref = Process.monitor(pid)

    Process.exit(client, :normal)
    assert_receive {^client_stream, %{}}, 5_000
  end


end
