defmodule Ace do

  defstruct [
    settings: nil
  ]

  def start_link(port, options) do
    spawn_link(__MODULE__, :ready, [])
  end

  def ready do
    receive do
      {:"$gen_server", from, {:accept}}
    end
  end

  def loop(state = %{socket: socket}) do
    receive do
      {ACE, frame} ->
        {:ok, frames} = constrain_frame(frame, state.settings)
        state = %{state | outbound: state.outbound ++ frames}
      {:ssl, ^socket, data} ->
        {buffer, state} = read_frames(buffer <> data, state)
        loop(buffer, state)
    end
  end

  def do_read_frames(buffer, state, socket) do
    {pending, state} = read_frames(buffer, state)
    expediate(pending, state, socket)
    do_read_frames(buffer, state, socket)
  end

  def read_frames(buffer, state) do
    case Frame.pop(data) do
      {:ok, {nil, buffer}} ->
        {buffer, state}
      {:ok, {frame, buffer}} ->
        {pending, state} = handle_frame(frame, state)
        read_frames(buffer, state)
    end
  end


  def handle_frame(new = %Settings{}, %{settings: nil}) do
    update_settings(new, nil)
  end
  def handle_frame(_, %{settings: nil}) do
    # Unexpected frame for startup
  end

  def handle_frame(frame = %Headers{fin: true}, state) do
    # start_stream(state.stream_supervisor)
    {:ok, pid} = start_link(Ace.Stream, :init, [[frame]])
    streams = Map.put(state.streams, frame.stream_id, pid)
  end
  def handle_frame(frame = %Headers{fin: false}, state) do
    {[], %{state | stream_head: [frame]}}
  end
  def handle_frame(frame = %Continuation{fin: true}, state) do
    stream_head = state.
  end
  def handle_frame(frame = %Data{}, state) do
    {:ok, pid} = fetch_stream(frame, state)
    Stream.send_data(pid, frame)
  end

  def start_stream(head = {:GET, "/foo", _ip}) do
    # start under dynamic supervisor
    Ace.FooController.start_link(head)
    {:ok, pid} = start_link(Ace.FooController, :init, [[frame]])

  end


end
