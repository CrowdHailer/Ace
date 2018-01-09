defmodule Ace.HTTP1.Client do
  @moduledoc """
  Simple API client that makes streaming easy.

  This client will send any `Raxx.Request` struct to a server.
  Raxx provedes basic tools for manipulating requests.

      request = Raxx.request(:POST, "/headers")
      |> Raxx.set_header("accept", "application/json")
      |> Raxx.set_body("Hello, httpbin")

  ## Synchronous dispatch

  Send a request and wait for the complete response.
  The response will be a complete `Raxx.Response`.

      {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
      # => {:ok, %Raxx.Response{...

      response.status
      # => 200

  ## Asynchronous responses

  `send_sync/2` is a wrapper around the underlying async api.
  To send requests asynchronously use `send/2`

      {:ok, channel_ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")

      receive do: {^channel_ref, %Raxx.Response{}} -> :ok
      receive do: {^channel_ref, %Raxx.Data{}} -> :ok
      receive do: {^channel_ref, %Raxx.Tail{}} -> :ok

  - *A response with no body will return only a `Raxx.Response`*
  - *A response with a body can return any number of `Raxx.Data` parts*

  ## Streamed data

  A request can have a body value of true indicating that the body will be sent later.
  The channel_ref returned when sending to an endpoint can be used to send follow up data.

      request = Raxx.request(:POST, "/headers")
      |> Raxx.set_header("accept", "application/json")
      |> Raxx.set_header("content-length", "13")
      |> Raxx.set_body(true)

      {:ok, channel_ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")

      data = Raxx.data("Hello, httpbin")
      {:ok, channel_ref} = Ace.HTTP1.Client.send(data, "http://httpbin.org")

      receive do: {^channel_ref, %Raxx.Response{}} -> :ok
      receive do: {^channel_ref, %Raxx.Data{}} -> :ok
      receive do: {^channel_ref, %Raxx.Tail{}} -> :ok

  NOTE: This module defines a `send/2` function clashes with `Kernel.send/2` if imported
  """

  import Kernel, except: [send: 2]
  require OK

  @type channel_ref :: {:http1, pid(), integer}
  # Could take a third argument that is a supervisor

  @doc """
  Send a request, or part of, to a remote endpoint.
  """
  @spec send(Raxx.Response.t, String.t) :: {:ok, channel_ref} | {:error, any()}
  def send(part, channel_ref = {:http1, endpoint, _}) do
    GenServer.call(endpoint, {:send, channel_ref, [part]})
  end
  def send(request, endpoint) do
    # `Endpoint.connect`
    # Linking to calling process is not an issue if never errors i.e. will always close
    # use monitor for exit normal
    {:ok, endpoint} = GenServer.start_link(__MODULE__, {:client, endpoint})

    # channel could be created with a monitor on the process
    # channel would be called link
    GenServer.call(endpoint, {:send, self(), [request]})
  end
  @doc """
  Send a request to a server and await the full response.

  The endpoint can be an open connection or host.
  see `send/2` for details
  """
  def send_sync(request, endpoint) do
    # ref should definetly contain a monitor
    OK.for do
      _ <- if Raxx.complete?(request), do: {:ok, nil}, else: {:error, :incomplete_request}
      ref <- send(request, endpoint)
      response <- await_response(ref)
    after
      response
    end
  end
  # Getting a channel should block until one is available.
  # But pipelining in HTTP/1 is just a bit weird

  def await_response(ref) do
    OK.for do
      head <- await_head(ref)
      # NOTE matches on no trailers
      {body, []} <- if head.body do
        await_tail(ref)
      else
        {:ok, {"", []}}
      end
    after
      %{head | body: body}
    end
  end
  defp await_head(ref) do
    timeout = 5_000
    receive do
      {^ref, head = %Raxx.Response{}} ->
        {:ok, head}
    after
      timeout ->
        {:error, {:timeout, timeout}}
    end
  end
  defp await_tail(ref, buffer \\ "") do
    receive do
      {^ref, %Raxx.Data{data: data}} ->
        await_tail(ref, buffer <> data)
      {^ref, %Raxx.Tail{headers: trailers}} ->
        {:ok, {buffer, trailers}}
    end
  end

  @enforce_keys [
    # Link to the TCP or SSL connection
    :socket,

    # reference to the
    :channel,

    :receive_state,

    :authority,
  ]
  defstruct @enforce_keys

  def init({:client, endpoint}) do
    case Ace.Socket.connect(endpoint) do
      {:ok, socket} ->
        %{authority: authority} = URI.parse(endpoint)
        state = %__MODULE__{
          socket: socket,
          channel: nil,
          receive_state: Ace.HTTP1.Parser.new(max_line_length: 2048),
          authority: authority
        }
        {:ok, state}
      {:error, reason} ->
        :ignore
    end
  end

  def handle_call({:send, worker, parts}, from, state = %{channel: nil}) do
    # NOTE change 1 to latest id for streaming.
    channel_number = 1

    channel_ref = {:http1, self(), channel_number}

    monitor = Process.monitor(worker)
    channel = {worker, monitor, channel_number}
    new_state = %{state | channel: channel}

    {packets, newer_state} = prepare(parts, new_state)
    IO.inspect(packets)

    Ace.Socket.send(state.socket, packets)
    {:reply, {:ok, channel_ref}, newer_state}
  end
  def handle_call({:send, channel_ref, parts}, from, state) do
    {packets, new_state} = prepare(parts, state)
    IO.inspect(packets)

    Ace.Socket.send(state.socket, packets)
    {:reply, {:ok, channel_ref}, new_state}
  end


  def handle_info({t, s, packet}, state = %{socket: {t, s}}) do
    IO.inspect(packet)
    case Ace.HTTP1.Parser.parse(packet, state.receive_state) do
      {:ok, {parts, receive_state}} ->
        {worker, channel_ref} = channel_ref(state.channel)
        Enum.each(parts, &Kernel.send(worker, {channel_ref, &1}))
        {:noreply, %{state | receive_state: receive_state}}
    end
  end
  def handle_info({transport, _socket}, state)
      when transport in [:tcp_closed, :ssl_closed] do
    {:stop, :normal, state}
  end

  defp prepare(parts, state) do
    Enum.reduce(parts, {[], state}, fn
      (request = %Raxx.Request{body: false}, {queue, state}) ->
        host = request.authority || state.authority
        headers = [{"host", host} | request.headers]

        start_line = [Atom.to_string(request.method), " ", raxx_to_path(request), " HTTP/1.1"]
        request = Enum.map([start_line] ++ raxx_header_lines(headers) ++ [""], fn(line) -> [line, "\r\n"] end)
        {queue ++ request, state}
      (request = %Raxx.Request{body: true}, {queue, state}) ->
        host = request.authority || state.authority
        headers = [{"host", host} | request.headers]

        header_lines = Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
        request = Enum.map([raxx_start_line(request)] ++ header_lines ++ [""], fn(line) -> [line, "\r\n"] end)
        {queue ++ request, state}
      (request = %Raxx.Request{body: body}, {queue, state}) when is_binary(body) ->
        content_length = :erlang.iolist_size(body)
        host = request.authority || state.authority
        headers = [{"host", host}, {"content-length", "#{content_length}"} | request.headers]
        header_lines = Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
        request = Enum.map([raxx_start_line(request)] ++ header_lines ++ [""], fn(line) -> [line, "\r\n"] end)

        {queue ++ request ++ [body], state}
      (request = %Raxx.Data{data: data}, {queue, state}) ->
        {queue ++ [data], state}
    end)
  end

  defp raxx_header(%{headers: headers}, header, default \\ :undefined) do

  end

  defp raxx_start_line(request) do
    [Atom.to_string(request.method), " ", raxx_to_path(request), " HTTP/1.1"]
  end

  defp raxx_header_lines(headers) do
    Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
  end

  defp raxx_to_path(%{path: segments, query: query}) do
    path = "/" <> Enum.join(segments, "/")
    query_string = URI.encode_query(query || %{})
    query = if query_string == "", do: "", else: "?" <> query_string
    [path, query]
  end

  defp channel_ref({worker, _monitor, id}, endpoint \\ self()) do
    {worker, {:http1, endpoint, id}}
  end
end
