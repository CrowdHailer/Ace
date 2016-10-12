defmodule Ace.TCP.Governor.Supervisor do
  use Supervisor

  def start_link(server_supervisor, listen_socket, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, {server_supervisor, listen_socket}, sup_opts)
  end

  # MODULE CALLBACKS

  def init({server_supervisor, listen_socket}) do
    # To speed up a server multiple process can be listening for a connection simultaneously.
    # In this case 5 Governors will start 5 Servers listening before a single connection is received.
    # FIXME make the acceptor pool size part of configuration
    children = [
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor], id: :"1"),
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor], id: :"2"),
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor], id: :"3"),
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor], id: :"4"),
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor], id: :"5")
    ]

    supervise(children, strategy: :one_for_one)
  end
end
