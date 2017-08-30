defmodule Ace.HTTP2.ClientTest do
  use ExUnit.Case

  alias Raxx.{
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
    request = Raxx.request(:GET, "/reqinfo")
    {:ok, stream} = Client.stream(client)
    :ok = Ace.HTTP2.send(stream, request)
    assert_receive {^stream, response = %Response{}}, 1_000
    assert 200 == response.status
    assert true == response.body

    assert_receive {^stream, %{data: data, end_stream: end_stream}}, 1_000
    assert true == end_stream

    assert String.contains?(data, "Method: GET")
    assert String.contains?(data, "Protocol: HTTP/2.0")
    assert String.contains?(data, "RequestURI: \"/reqinfo\"")
  end

  test "bidirectional streaming of data", %{client: client} do
    request = Raxx.request(:PUT, "/ECHO")
    |> Raxx.set_body(true)
    {:ok, stream} = Client.stream(client)
    :ok = Ace.HTTP2.send(stream, request)
    fragment = Raxx.fragment("foo")
    :ok = Ace.HTTP2.send(stream, fragment)
    assert_receive {^stream, response = %Response{}}, 1_000
    assert 200 == response.status
    assert true == response.body
    assert_receive {^stream, %{data: "FOO", end_stream: false}}, 1_000
    fragment = Raxx.fragment("bar")
    :ok = Ace.HTTP2.send(stream, fragment)
    assert_receive {^stream, %{data: "BAR", end_stream: false}}, 1_000
    # I do not think the remote closes stream if you do
    # :ok = Client.send_data(stream, "fin", true)
    # assert_receive {^stream, response = %{data: "FIN", end_stream: true}}, 1_000
  end

  test "read response with no body", %{client: client} do
    request = Raxx.request(:HEAD, "/")
    {:ok, stream} = Client.stream(client)
    :ok = Ace.HTTP2.send(stream, request)
    assert_receive {^stream, response = %Response{}}, 1_000
    assert 200 == response.status
    assert false == response.body
  end

  test "send synchronously without a body in response", %{client: client} do
    request = Raxx.request(:HEAD, "/")
    {:ok, response} = Client.send_sync(client, request)
    assert 200 == response.status
    assert false == response.body
  end

  test "send synchronously with a body in response", %{client: client} do
    request = Raxx.request(:GET, "/")
    {:ok, response} = Client.send_sync(client, request)
    assert 200 == response.status
    assert "<html>" <> _ = response.body
  end

  # test "handles Reset frames triggered by sending trailers", %{client: client} do
  #   {:ok, stream} = Client.stream(client)
  #   :ok = Client.send(stream, %{headers: [{"x-foo", "bar"}], end_stream: true})
  #   assert_receive {^stream, {:reset, :protocol_error}}, 1_000
  # end

  test "Get a push promise", %{client: client} do
    request = Raxx.request(:GET, "/serverpush")
    {:ok, stream} = Client.stream(client)
    :ok = Ace.HTTP2.send(stream, request)
    assert_receive {^stream, {:promise, {new_stream, _headers}}}, 1_000
    assert {:ok, %Response{}} = Client.collect_response(new_stream)
    assert_receive {^stream, {:promise, {new_stream, _headers}}}, 1_000
    assert {:ok, %Response{}} = Client.collect_response(new_stream)
    assert_receive {^stream, {:promise, {new_stream, _headers}}}, 1_000
    assert {:ok, %Response{}} = Client.collect_response(new_stream)
  end

  # DEBT note that logs include setup of unused client
  test "receive only one push promise" do
    {:ok, client} = Client.start_link("http2.golang.org", max_concurrent_streams: 1)
    request = Raxx.request(:GET, "/serverpush")
    {:ok, stream} = Client.stream(client)
    :ok = Ace.HTTP2.send(stream, request)
    assert_receive {^stream, {:promise, {new_stream, _headers}}}, 1_000
    assert {:ok, %Response{}} = Client.collect_response(new_stream)
    refute_receive {^stream, {:promise, {new_stream, _headers}}}, 1_000
  end

  # DEBT note that logs include setup of unused client
  test "Settings can prevent push promise" do
    {:ok, client} = Client.start_link("http2.golang.org", enable_push: false)
    request = Raxx.request(:GET, "/serverpush")
    {:ok, stream} = Client.stream(client)
    :ok = Ace.HTTP2.send(stream, request)
    refute_receive {^stream, {:promise, {_new_stream, _headers}}}, 1_000
  end

end
