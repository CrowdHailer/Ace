defmodule Ace.TCP.Acceptor do
  use GenServer

  def start_link(listen_socket, connection_supervisor) do
    pid = spawn_link(__MODULE__, :loop, [listen_socket, connection_supervisor])
    {:ok, pid}
  end

  def loop(listen_socket, connection_supervisor) do
    Supervisor.start_child(connection_supervisor, [listen_socket])
    loop(listen_socket, connection_supervisor)
  end

end
