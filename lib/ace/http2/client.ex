defmodule Ace.HTTP2.Client do
  @moduledoc """
  Send requests via HTTP/2 to a web service.

  *NB: all examples have this module aliased*

      alias Ace.HTTP2.Client

  ## Establish connection

  To make requests, a client must have an open connection to the server.
  A client process is started to manage this connection.

      {:ok, client} = Client.start_link("http2.golang.org")
      # OR
      {:ok, client} = Client.start_link({"http2.golang.org", 443})

  `Ace.HTTP2` only supports communication over TLS.
  It will attempt open a TLS connection for all port values.

  ## Reliable connections

  When a connection is lost the client process terminates.
  A reliable connection can be achieved by supervising the client process.

      children = [
        worker(Client, ["http2.golang.org", [name: MyApp.Client]])
      ]

  *A supervised client should be referenced by name.*

  ## Opening a stream

  Sending a request will automatically open a new stream.
  The request consists of the headers to send and if it has a body.
  If the body is `false` or included in the request as a binary,
  the stream will be half_closed(local) once request is sent.

  A client will accept a request with a binary value for the body.
  In this case the body is assumed complete with no further data to stream


      {:ok, stream} = Client.stream(client)
      request = Raxx.request(:GET, "/")
      |> Raxx.set_header("accept", "application/json")
      :ok = Ace.HTTP2.send(stream, request)

      {:ok, stream} = Client.stream(client)
      request = Raxx.request(:POST, "/")
      |> Raxx.set_header("content-length", "13")
      |> Raxx.set_body("Hello, World!")
      :ok = Ace.HTTP2.send(stream, request)

      request = Raxx.request(:POST, "/")
      |> Raxx.set_header("content-length", "13")
      |> Raxx.set_body(true)
      :ok = Ace.HTTP2.send(stream, request)
      fragment = Raxx.fragment("Hello, World!", true)
      {:ok, _} = Ace.HTTP2.send(stream, fragment)

  ## Receiving a response

  All data sent from the server if forwarded to the stream owner.
  The owner is the process that initiated the stream.

      receive do
        {^stream, %Raxx.Response{body: true}} ->
          :ok
      end
      receive do
        {^stream, %Raxx.Fragment{data: "Hello, World!", end_stream: end_stream}} ->
          :ok
      end

  *Response bodies will always be sent as separate messages to the stream owner.*

  A complete response may be built using the `collect_response/1`

      {:ok, %Raxx.Response{status: 200, body: "Hello, World!"}} = Client.collect_response(stream)

  ## Simple request response

  The Ace.Client aims to make the asynchronous stream of data easy.
  If this is not needed a synchronous interface is provided.

      {:ok, response} = Client.send_sync(connection, request)

  ## Examples

  See the client tests for more examples.
  """

  import Kernel, except: [send: 2]
  alias Ace.HTTP2.{
    Connection
  }

  @default_port 443

  @doc """
  Start a new client to establish connection with server.

  Authority consists of the combination of `{host, port}`
  """
  def start_link(authority, options \\ [])
  def start_link(authority, options) when is_binary(authority) do
    start_link({authority, @default_port}, options)
  end
  def start_link({host, port}, options) when is_binary(host) do
    host = :erlang.binary_to_list(host)
    start_link({host, port}, options)
  end
  def start_link({host, port}, options) do
    ssl_options = Keyword.take(options, [:cert, :certfile, :key, :keyfile])
    {:ok, settings} = Ace.HTTP2.Settings.for_client(options)
    GenServer.start_link(Connection, {:client, {host, port}, settings, ssl_options}, options)
  end

  @doc """
  Start a new stream within a running connection.

  Stream will start in idle state.
  """
  def stream(connection) do
    GenServer.call(connection, {:new_stream, self()})
  end

  @doc """
  Collect all the parts streamed to a client as a single response.
  """
  def collect_response(stream) do
    receive do
      {^stream, response = %Raxx.Response{body: body}} ->
        if body == false do
          {:ok, response}
        else
          {:ok, body} = read_body(stream)
          {:ok, %{response | body: body}}
        end
      after
        1_000 ->
          :no_headers
    end
  end

  @doc """
  Send a complete request and wait for a complete response.

  NOTE the request must have have body as a binary or `false`.
  """
  def send_sync(connection, request) do
    if Raxx.complete?(request) do
      {:ok, stream} = stream(connection)
      :ok = Ace.HTTP2.send(stream, request)
      # send - transmit, publish, dispatch, put, relay, emit, broadcast
      if is_binary(request.body) do
        fragment = Raxx.fragment(request.body, true)
        :ok = Ace.HTTP2.send(stream, fragment)
      end
      collect_response(stream)
    else
      raise "needs to be a complete request"
    end
  end

  defp read_body(stream, buffer \\ "") do
    receive do
      {^stream, %Raxx.Fragment{data: data, end_stream: end_stream}} ->
        buffer = buffer <> data
        read_body(stream, buffer)
      {^stream, %Raxx.Trailer{}} ->
        {:ok, buffer}
      after
        1_000 ->
          :timeout
    end
  end

  # terminate :shutdown/:normal for GoAway
  # terminate :abnormal for lost
end
