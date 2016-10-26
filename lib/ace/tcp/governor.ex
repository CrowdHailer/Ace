defmodule Ace.TCP.Governor do
  @moduledoc """
  The governor acts to throttle the creation of servers.

  A governor process starts a server under the supervision of a server supervisor.
  It will then wait until the server has accepted a connection.
  Once it's server has accepted a connection the governor will start a new server.
  """

  @doc """
  Start a new governor, linked to the calling process.
  """
  @spec start_link(:inet.socket, supervisor) :: {:ok, pid} when
    supervisor: pid()
  def start_link(listen_socket, server_supervisor) do
    pid = spawn_link(__MODULE__, :loop, [listen_socket, server_supervisor])
    {:ok, pid}
  end

  @doc false
  def loop(listen_socket, server_supervisor) do
    {:ok, server} = Supervisor.start_child(server_supervisor, [])
    :ok = Ace.TCP.Server.accept(server, listen_socket)
    loop(listen_socket, server_supervisor)
  end

end
