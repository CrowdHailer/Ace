defmodule Ace.TCP.Governor.Supervisor do
  @moduledoc """
  To ensure the pool of listening servers is kept constant, the governor processes are supervised.

  The each governor in the pool is replaced on a one for one basis.
  """
  use Supervisor

  @doc """
  Starts a supervised pool of governor processes.
  """
  def start_link(server_supervisor, listen_socket, acceptors, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, {server_supervisor, listen_socket, acceptors}, sup_opts)
  end

  ## SERVER CALLBACKS

  def init({server_supervisor, listen_socket, acceptors}) do
    # To speed up a server multiple process can be listening for a connection simultaneously.
    # In this case n Governors will start n Servers listening before a single connection is received.
    children = for i <- 1..acceptors do
      worker(Ace.TCP.Governor, [listen_socket, server_supervisor], id: "#{i}")
    end

    supervise(children, strategy: :one_for_one)
  end
end
