defmodule Ace.HTTP2.Client do
  @moduledoc """
  Send requests via HTTP/2 to a web service.

  *NB: all examples have this module, `Ace.Request` and `Ace.Response` aliased*

      alias Ace.HTTP2.Client
      alias Ace.Request
      alias Ace.Response

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
        {^stream, %{data: "Hello, World!", end_stream: end_stream}} ->
          :ok
      end

  *Response bodies will always be sent as separate messages to the stream owner.*

  A complete response may be built using the `collect_response/1`

      {:ok, %Response{status: 200, body: "Hello, World!"}} = Client.collect_response(stream)

  ## Simple request response

  The Ace.Client aims to make the asynchronous stream of data easy.
  If this is not needed a synchronous interface is provided.

      {:ok, response} = Client.send_sync(connection, request)

  ## Examples

  See the client tests for more examples.
  """

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
    GenServer.start_link(Connection, {:client, {host, port}}, options)
  end

  @doc """
  Send a request that will start a new stream to the server.

  This function returns a stream reference send and receive data.
  If requests has body `true` then data may be streamed using `send_data/2`.
  """
  def stream(pid, request) do
    {:ok, stream} = GenServer.call(pid, {:new_stream, self()})
    # send - transmit, publish, dispatch, put, relay, emit, broadcast
    :ok = GenServer.call(pid, {:send, stream, request})
    {:ok, stream}
  end

  @doc """
  Add data to an open stream.
  """
  def send_data(stream = {:stream, connection, _, _}, data, end_stream \\ false) do
    :ok = GenServer.call(connection, {:send, stream, %{data: data, end_stream: end_stream}})
  end

  @doc """
  Collect all the parts streamed to a client as a single response.
  """
  def collect_response(stream) do
    receive do
      {^stream, response = %Ace.Response{body: body}} ->
        if body == false do
          {:ok, response}
        else
          {:ok, body} = read_body(stream)
          {:ok, %{response | body: body}}
        end
    end
  end

  @doc """
  Send a complete request and wait for a complete response.

  NOTE the request must have have body as a binary or `false`.
  """
  def send_sync(pid, request) do
    if Ace.Request.complete?(request) do
      {:ok, stream} = GenServer.call(pid, {:new_stream, self()})
      # send - transmit, publish, dispatch, put, relay, emit, broadcast
      :ok = GenServer.call(pid, {:send, stream, request})
      if is_binary(request.body) do
        :ok = GenServer.call(pid, {:send, stream, %{data: request.body, end_stream: true}})
      end
      collect_response(stream)
    else
      raise "needs to be a complete request"
    end
  end

  defp read_body(stream, buffer \\ "") do
    receive do
      {^stream, %{data: data, end_stream: end_stream}} ->
        buffer = buffer <> data
        if end_stream do
          {:ok, buffer}
        else
          read_body(stream, buffer)
        end
    end
  end

  # terminate :shutdown/:normal for GoAway
  # terminate :abnormal for lost
end
