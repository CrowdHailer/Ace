defmodule Ace.Governor.Supervisor do
  @moduledoc """
  To ensure the pool of listening servers is kept constant, the governor processes are supervised.

  The each governor in the pool is replaced on a one for one basis.
  """
  use Supervisor

  @doc """
  Starts a supervised pool of governor processes.
  """
  @spec start_link(pid, :inet.socket, non_neg_integer) :: {:ok, pid}
  def start_link(server_supervisor, listen_socket, acceptors) do
    Supervisor.start_link(__MODULE__, {server_supervisor, listen_socket, acceptors}, [])
  end

  ## SERVER CALLBACKS

  @doc false
  def init({server_supervisor, listen_socket, acceptors}) do
    # To speed up a server multiple process can be listening for a connection simultaneously.
    # In this case n Governors will start n Servers listening before a single connection is received.
    children = for i <- 1..acceptors do
      worker(Ace.Governor, [listen_socket, server_supervisor], id: "#{i}")
    end

    # The number of governors should be kept constent, for each governor that crashes a replacement should be started.
    supervise(children, strategy: :one_for_one)
  end
end
