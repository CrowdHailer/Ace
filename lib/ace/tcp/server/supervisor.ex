defmodule Ace.TCP.Server.Supervisor do
  @moduledoc """
  Supervise a collection of servers, that are listening or handling connections.

  Individual server processes can be stared from a supervisor,
  however recommended is to provide a constant sized number of accepting servers use a governor pool.
  """
  use Supervisor

  @doc """
  Start a new server supervisor.

  Each worker will be started with the same app defined behaviour.
  """
  def start_link(app, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, app, sup_opts)
  end

  ## MODULE CALLBACKS

  def init(app) do
    children = [
      worker(Ace.TCP.Server, [app], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
