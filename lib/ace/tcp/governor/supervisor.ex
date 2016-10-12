defmodule Ace.TCP.Governor.Supervisor do
  use Supervisor

  def start_link(server_supervisor, listen_socket, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, {server_supervisor, listen_socket}, sup_opts)
  end

  # MODULE CALLBACKS

  def init({server_supervisor, listen_socket}) do
    children = [
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
