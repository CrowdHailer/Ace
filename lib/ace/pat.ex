# defmodule Ace.HTTP2.PersistentClient do
#   def start_link(uri, options \\ [])
#   def start_link(uri, options) do
#     %{scheme: "https", host: host, port: port} = URI.parse(uri)
#     GenServer.start_link(__MODULE__, {:ssl, host, port, options})
#   end
#
#   def init(state = {:ssl, host, port, options}) do
#     # ssl connect new socket state
#     # Use Socket.connect
#     send(self(), :connect)
#     {:ok, state}
#   end
#
#   def handle_call(msg = {:send, _}, from, state = %{socket: nil}) do
#     case connect(state.location) do
#       {:ok, socket} ->
#         handle_call(msg, from, %{state | socket: socket})
#       {:error, reason} ->
#         {:reply, {:error, reason}, state}
#     end
#   end
#
#   # use when msg_type in [:ping, :send]
#   def handle_call(msg = {:ping, _}, from, state = %{socket: nil}) do
#     case connect(state.location) do
#       {:ok, socket} ->
#         handle_call(msg, from, %{state | socket: socket})
#       {:error, reason} ->
#         {:reply, {:error, reason}, state}
#     end
#   end
#
#   # Don't need to tackle monitor problem for pat
#   def handle_call({:send, pid, parts}, _from, state) when is_pid do
#     {:ok, new_stream} = Stream.add_stream
#     # stream_for(pid, make_ref)
#     # Queue to send
#     # Process.send(self(), :send_available)
#     # Doing it like this mean lots of GenServer.call's get bundled into a single packet
#     {:reply, {:ok, Stream.exchange_identifier(stream, self())}, merge_stream}
#   end
#
#   def handle_call(:cancel, exchange_ref, state) do
#
#   end
#   # ping does not use refs
#   def handle_call({:ping, identifier}, from, state = %{socket: socket}) do
#     state = put_in(state, [:pings, identifier], from)
#     :ok = Socket.send(socket, Frame.Ping.new(identifier))
#     {:noreply, state}
#   end
#
#   def handle_call(:stop, _from, state) do
#
#   end
#
#   def handle_info(:connect, %{location: location}) do
#     case connect(location) do
#       _ -> :ok
#     end
#   end
#   def handle_info(:send_available, %{socket: socket}) do
#     case connect(location) do
#       _ -> :ok
#     end
#   end
#
#   def handle_info() do
#
#   end
# end
# defmodule Pat do
#   # child_spec can start a Client
#   defmodule Client do
#     def start_link() do
#
#     end
#
#     def send(notification, retries) do
#       Ace.HTTP2.PersistentClient.send
#     end
#   end
#
# end
