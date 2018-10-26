defmodule Ace.Governor do
  @moduledoc """
  A governor maintains servers ready to handle clients.

  A governor process starts with a reference to supervision that can start servers.
  It will then wait until the server has accepted a connection.
  Once it's server has accepted a connection the governor will start a new server.
  """

  use GenServer

  @enforce_keys [:server_supervisor, :listen_socket, :server, :monitor]
  defstruct @enforce_keys

  def start_link(server_supervisor, listen_socket) when is_pid(server_supervisor) do
    initial_state = %{
      server_supervisor: server_supervisor,
      listen_socket: listen_socket,
      server: nil,
      monitor: nil
    }

    GenServer.start_link(__MODULE__, initial_state)
  end

  def child_spec({endpoint_supervisor, listen_socket}) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [endpoint_supervisor, listen_socket]},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end

  @impl GenServer
  def init(initial_state) do
    new_state = start_server(initial_state)
    {:ok, new_state}
  end

  @impl GenServer
  # DEBT should match response are `{:ok, server}` or `{:error, reason}`
  def handle_info({monitor, _response}, state = %{monitor: monitor, server: server}) do
    true = Process.unlink(server)
    true = Process.demonitor(monitor)

    new_state = start_server(%{state | monitor: nil, server: nil})
    {:noreply, new_state}
  end

  def handle_info({:DOWN, monitor, :process, _server, :normal}, state = %{monitor: monitor}) do
    # Server process has terminated so existing references are irrelevant
    new_state = start_server(%{state | monitor: nil, server: nil})
    {:noreply, new_state}
  end

  # Messages from previously monitored process can arrive when the connection response quickly and exits normally.
  def handle_info({:DOWN, _, :process, _, :normal}, state) do
    {:noreply, state}
  end

  # function head ensures that only one server is being monitored at a time
  defp start_server(state = %{server: nil, monitor: nil}) do
    # Starting a server process must always succeed, before accepting on a connection it has no external influences.
    {:ok, server} = Supervisor.start_child(state.server_supervisor, [])

    # The behaviour of a server is to always after creation, therefore linking should always succeed.
    true = Process.link(server)

    # Creates a unique reference that we can also use to correlate the call to accept on a given socket.
    monitor = Process.monitor(server)

    # Simulate a `GenServer.call` but without blocking on a receive loop.
    send(server, {:"$gen_call", {self(), monitor}, {:accept, state.listen_socket}})

    %{state | monitor: monitor, server: server}
  end
end
