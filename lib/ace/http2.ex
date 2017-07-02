defmodule Ace.HTTP2 do
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @default_settings %{}

  def preface() do
    @preface
  end

  defstruct [
    settings: nil,
    socket: nil
  ]

  use GenServer
  def start_link(listen_socket) do
    GenServer.start_link(__MODULE__, listen_socket)
  end

  def init(listen_socket) do
    {:ok, {:listen_socket, listen_socket}, 0}
  end
  def handle_info(:timeout, {:listen_socket, listen_socket}) do
    {:ok, socket} = :ssl.transport_accept(listen_socket)
    :ok = :ssl.ssl_accept(socket)
    {:ok, "h2"} = :ssl.negotiated_protocol(socket)
    :ssl.send(socket, <<0::24, 4::8, 0::8, 0::32>>)
    :ssl.setopts(socket, [active: :once])
    {:noreply, {:pending, %__MODULE__{socket: socket}}}
  end
  def handle_info({:ssl, _, @preface <> data}, {:pending, state}) do
    consume(data, state)
  end
  def handle_info({:ssl, _, data}, state) do
    consume(data, state)
  end

  def consume(buffer, state) do
    {frame, unprocessed} = Ace.HTTP2.Frame.read_next(buffer) # + state.settings )
    # IO.inspect(frame)
    # IO.inspect(unprocessed)
    if frame do
      {outbound, state} = consume_frame(frame, state)
      :ok = :ssl.send(state.socket, outbound)
      consume(unprocessed, state)
    else
      :ssl.setopts(state.socket, [active: :once])
      {:noreply, state}
    end
  end

  def consume_frame(<<l::24, 4::8, 0::8, 0::1, 0::31, payload::binary>>, state = %{settings: nil}) do
    new_settings = update_settings(payload)
    {[<<0::24, 4::8, 1::8, 0::32>>], %{state | settings: new_settings}}
  end
  def consume_frame(<<8::24, 6::8, 0::8, 0::32, data::64>>, settings) do
    {[<<8::24, 6::8, 1::8, 0::32, data::64>>], settings}
  end
  def consume_frame(<<4::24, 8::8, 0::8, 0::32, data::32>>, settings) do
    {[], settings}
  end
  def consume_frame(_, state = %{settings: nil}) do
    :invalid_first_frame
  end

  def update_settings(new, old \\ @default_settings) do
    %{}
  end

  #
  # def ready do
  #   receive do
  #     {:"$gen_server", from, {:accept, socket}} ->
  #       :ssl.accept
  #   end
  # end
  #
  # def loop(state = %{socket: socket}) do
  #
  #   receive do
  #     {ACE, frame} ->
  #       {:ok, frames} = constrain_frame(frame, state.settings)
  #       state = %{state | outbound: state.outbound ++ frames}
  #     {:ssl, ^socket, data} ->
  #       {buffer, state} = read_frames(buffer <> data, state)
  #       loop(buffer, state)
  #   end
  # end
  #
  # def do_read_frames(buffer, state, socket) do
  #   {pending, state} = read_frames(buffer, state)
  #   expediate(pending, state, socket)
  #   do_read_frames(buffer, state, socket)
  # end
  #
  # def read_frames(buffer, state) do
  #   case Frame.pop(data) do
  #     {:ok, {nil, buffer}} ->
  #       {buffer, state}
  #     {:ok, {frame, buffer}} ->
  #       {pending, state} = handle_frame(frame, state)
  #       read_frames(buffer, state)
  #   end
  # end
  #
  #
  # def handle_frame(new = %Settings{}, %{settings: nil}) do
  #   update_settings(new, nil)
  # end
  # def handle_frame(_, %{settings: nil}) do
  #   # Unexpected frame for startup
  # end
  #
  # def handle_frame(frame = %Headers{fin: true}, state) do
  #   # start_stream(state.stream_supervisor)
  #   {:ok, pid} = start_link(Ace.Stream, :init, [[frame]])
  #   streams = Map.put(state.streams, frame.stream_id, pid)
  # end
  # def handle_frame(frame = %Headers{fin: false}, state) do
  #   {[], %{state | stream_head: [frame]}}
  # end
  # def handle_frame(frame = %Continuation{fin: true}, state) do
  #   stream_head = state.
  # end
  # def handle_frame(frame = %Data{}, state) do
  #   {:ok, pid} = fetch_stream(frame, state)
  #   Stream.send_data(pid, frame)
  # end
  #
  # def start_stream(head = {:GET, "/foo", _ip}) do
  #   # start under dynamic supervisor
  #   Ace.FooController.start_link(head)
  #   {:ok, pid} = start_link(Ace.FooController, :init, [[frame]])
  #
  # end


end
