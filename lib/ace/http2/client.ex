defmodule Ace.HTTP2.Client do
  @moduledoc """
  Send requests via HTTP/2 to a web service.

  *NB: all examples have this module, Ace.Request and Ace.Response aliased*

      alias Ace.HTTP2.Client

  ## Establish connection

  To make requests, a client must have an open connection to the server.
  A client process is started to manage this connection.

      {:ok, client} = Client.start_link({"http2.golang.org", 443})

  Ace.HTTP2 only supports communication over TLS.
  It will attempt open a TLS connection for all port values.

  ## Reliable connections

  When a connection is lost the client process terminates.
  A reliable connection can be achieved by supervising the client process.

      children = [
        worker(Client, [{"http2.golang.org", 443}, [name: :golang]])
      ]

  *A supervised client should be referenced by name.*

  ## Opening a stream

  Sending a request will automatically open a new stream.
  The request consists of the headers to send and if it has a body.
  If the body is `false` the stream will be half_closed(local) once request is sent.

  A client will accept a request with a binary value for the body.
  In this case the body is assumed complete with no further data to stream

      request = Request.new(:GET, "/", [{"accept", "application/json"}], false)
      {:ok, stream} = Client.stream(client, request)

      request = Request.new(:POST, "/", [{"content-length", "13"}], "Hello, World!")
      {:ok, stream} = Client.stream(client, request)

      request = Request.new(:POST, "/", [{"content-length", "13"}], true)
      {:ok, stream} = Client.stream(client, request)
      {:ok, _} = Client.send_data(stream, "Hello, World!", end_stream: true)

  ## Receiving a response

  All data sent from the server if forwarded to the stream owner.
  The owner is the process that initiated the stream.

      receive do
        {^stream, %Response{body: true}} ->
          :ok
      end
      receive do
        {^stream, %Content{data: "Hello, World!"}} ->
          :ok
      end

  *Response bodies will always be sent as separate messages to the stream owner.*

  A complete response may be built using the `collect_response/1`

      {:ok, %Response{status: 200, body: "Hello, World!"}} = Client.collect_response(stream)

  ## Simple request response

  The Ace.Client aims to make the asynchronous stream of data easy.
  If this is not needed a synchronous interface is provided.

      {:ok, response} = Client.send_sync(connection, request)
  """

  alias Ace.HTTP2.{
    Connection
  }

  @doc """
  Start a new client to establish connection with server.

  Authority consists of the combination of `{host, port}`
  """
  def start_link(authority, options \\ [])
  def start_link({host, port}, options) when is_binary(host) do
    host = :erlang.binary_to_list(host)
    GenServer.start_link(Connection, {:client, {host, port}}, options)
  end

  def send(client, stuff) do
    GenServer.call(client, {:request, stuff, self()})
  end

  # terminate :shutdown/:normal for GoAway
  # terminate :abnormal for lost
end
