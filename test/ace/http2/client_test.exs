defmodule Ace.HTTP2.ClientTest do
  use ExUnit.Case

  alias Ace.{
    Request,
    Response
  }
  alias Ace.HTTP2.{
    Client
  }

  setup do
    {:ok, client} = Client.start_link("http2.golang.org")
    {:ok, %{client: client}}
  end

  test "sends correct request headers", %{client: client} do
    request = Request.get("/reqinfo")
    {:ok, stream} = Client.stream(client, request)
    assert_receive {^stream, response = %Response{}}, 1_000
    assert 200 == response.status
    assert true == response.body

    assert_receive {^stream, response = %{data: data, end_stream: end_stream}}, 1_000
    assert true == end_stream

    assert String.contains?(data, "Method: GET")
    assert String.contains?(data, "Protocol: HTTP/2.0")
    assert String.contains?(data, "RequestURI: \"/reqinfo\"")
  end

  test "bidirectional streaming of data", %{client: client} do
    request = Request.put("/ECHO", [], true)
    {:ok, stream} = Client.stream(client, request)
    :ok = Client.send_data(stream, "foo")
    assert_receive {^stream, response = %Response{}}, 1_000
    assert 200 == response.status
    assert true == response.body
    assert_receive {^stream, response = %{data: "FOO", end_stream: false}}, 1_000
    :ok = Client.send_data(stream, "bar")
    assert_receive {^stream, response = %{data: "BAR", end_stream: false}}, 1_000
    # I do not think the remote closes stream if you do
    # :ok = Client.send_data(stream, "fin", true)
    # assert_receive {^stream, response = %{data: "FIN", end_stream: true}}, 1_000
  end

  test "read response with no body", %{client: client} do
    request = Request.new(:HEAD, "/", [], false)
    {:ok, stream} = Client.stream(client, request)
    assert_receive {^stream, response = %Response{}}, 1_000
    assert 200 == response.status
    assert false == response.body
  end

  test "send synchronously without a body in response", %{client: client} do
    request = Request.new(:HEAD, "/", [], false)
    {:ok, response} = Client.send_sync(client, request)
    assert 200 == response.status
    assert false == response.body
  end

  test "send synchronously with a body in response", %{client: client} do
    request = Request.new(:GET, "/", [], false)
    {:ok, response} = Client.send_sync(client, request)
    assert 200 == response.status
    assert "<html>" <> _ = response.body
  end

  test "handles Reset frames triggered by sending trailers", %{client: client} do
    {:ok, stream} = Client.stream(client)
    :ok = Client.send(stream, %{headers: [{"x-foo", "bar"}], end_stream: true})
    assert_receive {^stream, {:reset, :protocol_error}}, 1_000
  end

  test "Get a push promise", %{client: client} do
    request = Request.get("/serverpush")
    {:ok, stream} = Client.stream(client, request)
    assert_receive {^stream, {:promise, {new_stream, headers}}}, 1_000
    assert {:ok, r} = Client.collect_response(new_stream)
    assert_receive {^stream, {:promise, {new_stream, headers}}}, 1_000
    assert {:ok, r} = Client.collect_response(new_stream)
    assert_receive {^stream, {:promise, {new_stream, headers}}}, 1_000
    assert {:ok, r} = Client.collect_response(new_stream)
  end

end
