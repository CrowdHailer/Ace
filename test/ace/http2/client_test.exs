defmodule Ace.HTTP2.ClientTest do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Frame
  }

  setup do
    {_server, port} = Support.start_server(self())
    {:ok, %{port: port}}
  end

  test "fetch request info" do
    # # Client auto add authority + scheme
    # %Request{
    #   # scheme is nil use :https
    #   # authority is nil fetch from connection
    #   path:
    #   method:
    #   headers:
    #   body: :true, :false, "Here is the whole body" # binary or true
    # }
    # %Response{
    #   status:
    #   headers:
    #   body: same
    # }
    # %Data/Payload/Body{
    # end_stream: true/false
    # }
    # %Trailers{
    #   headers: []
    # }
    #
    # def end_stream(body: body) when is_binary(body) do
    #   true
    # end
    # def end_stream(body: body) do
    #   !body
    # end
    #
    # def collect([r, data, dta]) do
    #   squash in data
    # end
    #
    #
    # {:ok, stream} = Client.stream(connection, request)
    # {:ok, stream} = Client.stream(connection, :GET, "/foo", [], false)
    # {:ok, stream} = Client.stream(connection, Request.new(:GET, "/foo", [], false))
    # Request.get("/path", [{"content-length", "4"}], authority: "foo.com", scheme: :http)
    #
    # :ok = Client.send_data("blh", :end)
    #
    # {:ok, %Response{, body: true}} = Client.response(ref)
    # {:ok, %Response{, body: true}} = Client.read_response(ref)
    # {:ok, %Payload{, data: "Hello"}} = Client.read_body(ref)
    # # gather accumulate accrue
    # {:ok, %Response{, body: "the whole response"}} = Client.collect_response(ref)
    #
    # {:ok, response} = Client.send_sync(connection, Request.new(:GET, "/foo", [], false))
    # # THis should raise an error as incorrect usage
    # {:error, :body_must_be_provided_for_syn_sending} = Client.send_sync(connection, Request.new(:POST, "/foo", [], true))
    #
    #
    #
    #
    #
    # # Always make streaming data second step
    # # 1
    # {:ok, stream} = Client.stream_up(connection, method, path, headers)
    # :ok = Client.send_data(stream, "some")
    # :ok = Client.send_data(stream, "more")
    # :ok = Client.send_data(stream, "stuff.", true)
    # # 2
    # {:ok, stream} = Client.open_stream(connection, request)
    # {:ok, stream} = Client.stream_data(request)
    # {:ok, stream} = Client.end_stream(request)
    # {:ok, response} = Clieant.read_stream(stream)
    #
    # {:ok, {response, stream}} = Client.stream_down(method, path, headers, payload)
    #
    #
    #
    # {:ok, response} = Client.request(method, path, headers, payload)


    {:ok, client} = Ace.HTTP2.Client.start_link({"http2.golang.org", 443})
    {:ok, ref} = Ace.HTTP2.Client.send(client, [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/serverpush"}
      ])
    assert_receive 5, 7_000
  end

  test "", %{port: port} do
    # Ace.Client.start_link({"localhost", 8080})
    # HTTP1 + 2
    {:ok, client} = Ace.HTTP2.Client.start_link({"localhost", port})

    {:ok, ref} = Ace.HTTP2.Client.send(client, [
      {":scheme", "https"},
      {":authority", "example.com"},
      {":method", "GET"},
      {":path", "/"}
    ])
    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})
    assert_receive {stream, request}, 1_000
    Ace.HTTP2.StreamHandler.send_to_client(stream, %{headers: [{":status", "200"}], end_stream: false})
    Ace.HTTP2.StreamHandler.send_to_client(stream, %{data: "Hello, world!", end_stream: true})
    assert_receive {^ref, response}, 1_000
    assert_receive {^ref, response}, 1_000
    Process.sleep(5_000)
    # request = Ace.Request.get("/hello")
    #
    # Await full response
    # {:ok, ref} = Ace.HTTP2.Client.send_sync
  end
end
