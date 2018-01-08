defmodule Ace.HTTP1.Client do
  @moduledoc """
  Build request in parts

  request

  Ace.HTTP1.Client.send_sync(request, host)
  #=>{:ok, response}

  {:ok, ref} send
  cancel (ref)


  await_response

  NOTE: This module defines a `send/2` function that would clash with the `Kernel` implementation
  """

  import Kernel, except: [send: 2]


  # Could take a third argument that is a supervisor
  def send(request, endpoint) do
    # `Endpoint.connect`
    # Linking to calling process is not an issue if never errors i.e. will always close
    # use monitor for exit normal
    {:ok, endpoint} = GenServer.start_link(__MODULE__, {:client, endpoint})

    # channel could be created with a monitor on the process
    # channel would be called link
    GenServer.call(endpoint, {:send, self(), [request]})
  end
  def send_sync(request, endpoint) do
    # ref should definetly contain a monitor
    {:ok, ref} = send(request, endpoint)
    {:ok, head} = await_response(ref)
  end
  # Getting a channel should block until one is available.
  # But pipelining in HTTP/1 is just a bit weird

  def await_response(ref) do
    {:ok, head} = await_head(ref)
    # NOTE matches on no trailers
    {:ok, {body, []}} = if head.body do
      await_tail(ref)
    else
      {:ok, {"", []}}
    end
    {:ok, %{head | body: body}}
  end
  defp await_head(ref) do
    receive do
      {^ref, head = %Raxx.Response{}} ->
        {:ok, head}
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

    :receive_state
  ]
  defstruct @enforce_keys

  def init({:client, endpoint}) do
    {:ok, socket} = Ace.Socket.connect(endpoint)

    state = %__MODULE__{
      socket: socket,
      channel: nil,
      receive_state: Ace.HTTP1.Parser.new(max_line_length: 2048)
    }
    {:ok, state}
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
        "//" <> host = "#{%URI{authority: request.authority}}"
        headers = [{"host", host} | request.headers]

        start_line = [Atom.to_string(request.method), " ", raxx_to_path(request), " HTTP/1.1"]
        header_lines = Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
        request = Enum.map([start_line] ++ header_lines ++ [""], fn(line) -> [line, "\r\n"] end)
        {queue ++ request, state}
    end)
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
