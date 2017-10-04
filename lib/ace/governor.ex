defmodule Ace.Governor do
  @moduledoc """
  A governor maintains servers ready to handle clients.

  A governor process starts with a reference to supervision that can start servers.
  It will then wait until the server has accepted a connection.
  Once it's server has accepted a connection the governor will start a new server.
  """

  use GenServer

  def child_spec({endpoint_supervisor, listen_socket}) do
    # DEBT is module previously checked to implement Raxx.Application or Raxx.Server
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [endpoint_supervisor, listen_socket]},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end

  def start_link(endpoint_supervisor, listen_socket) when is_pid(endpoint_supervisor) do
    GenServer.start_link(__MODULE__, {listen_socket, endpoint_supervisor})
  end

  @impl GenServer
  def init(state = {listen_socket, endpoint_supervisor}) do
    send(self(), :start)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:start, state = {listen_socket, endpoint_supervisor}) do
    {:ok, server} = Supervisor.start_child(endpoint_supervisor, [])
    Ace.HTTP.Server.accept_connection(server, listen_socket)
    handle_info(:start, state)
  end
end
