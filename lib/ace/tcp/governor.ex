defmodule Ace.TCP.Governor do
  @doc """
  The governor process acts to throttle the creation of servers.

  The process starts a server under the supervision of a server supervisor.
  It will then wait untill the server has accepted a connection.
  Once it's server has accepted a connection it will repeat the process.
  """
  use GenServer

  def start_link(listen_socket, server_supervisor) do
    pid = spawn_link(__MODULE__, :loop, [listen_socket, server_supervisor])
    {:ok, pid}
  end

  def loop(listen_socket, server_supervisor) do
    {:ok, server} = Supervisor.start_child(server_supervisor, [])
    :ok = Ace.TCP.Server.accept(server, listen_socket)
    loop(listen_socket, server_supervisor)
  end

end
