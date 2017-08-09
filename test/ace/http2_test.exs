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

  test "full request is streamed from client to server", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.post("/", [{"content-type", "text/plain"}], true)
    :ok = Client.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, received = %Request{}}, 1_000
    assert received.path == request.path

    :ok = Client.send_data(client_stream, "Hello, ")
    assert_receive {^server_stream, %{data: "Hello, ", end_stream: false}}, 1_000

    :ok = Client.send(client_stream, %{headers: [{"x-foo", "bar"}], end_stream: true})
    assert_receive {^server_stream, %{headers: [{"x-foo", "bar"}], end_stream: true}}, 1_000
  end

  # Check sending complete request ends stream with/out body

  # Client should not break protocol
  # disallow sending on an ended stream
  # disallow sending trailers which do not end stream

  test "full response is streamed from server to client", %{port: port} do
    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Request.get("/", [{"content-type", "text/plain"}])
    :ok = Client.send(client_stream, request)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})

    assert_receive {server_stream, %Request{}}, 1_000

    response = Response.new(200, [{"content-type", "text/plain"}], true)
    # TODO return ok
    Server.send(server_stream, response)
    assert_receive {client_stream, received = %Response{}}, 1_000
    assert 200 == received.status
  end

  # Check sending complete request ends stream with/out body
end
