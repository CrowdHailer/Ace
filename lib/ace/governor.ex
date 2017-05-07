defmodule Ace.Governor do
  @moduledoc """
  A governor maintains servers ready to handle clients.

  A governor process starts a server under the supervision of a server supervisor.
  It will then wait until the server has accepted a connection.
  Once it's server has accepted a connection the governor will start a new server.
  """

  use GenServer
  alias Ace.Server
  import Server, only: [connection_ack: 2]

  @doc """
  Start a new governor, linked to the calling process.
  """
  @spec start_link(:inet.socket, supervisor) :: {:ok, pid} when
    supervisor: pid()
  def start_link(listen_socket, server_supervisor) do
    GenServer.start_link(__MODULE__, {listen_socket, server_supervisor})
  end

  ## Server callbacks

  def init({listen_socket, server_supervisor}) do
    {:ok, server} = Supervisor.start_child(server_supervisor, [])
    true = Process.link(server)
    Process.monitor(server) # Normal exit will stop governor
    {:ok, ref} = Server.accept_connection(server, listen_socket)
    {:ok, {listen_socket, server_supervisor, ref, server}}
  end

  def handle_info(connection_ack(ref, _), {listen_socket, server_supervisor, ref, server}) do
    true = Process.unlink(server)
    {:ok, new_server} = Supervisor.start_child(server_supervisor, [])
    true = Process.link(new_server)
    Process.monitor(server)
    {:ok, new_ref} = Server.accept_connection(new_server, listen_socket)
    {:noreply, {listen_socket, server_supervisor, new_ref, new_server}}
  end

end
