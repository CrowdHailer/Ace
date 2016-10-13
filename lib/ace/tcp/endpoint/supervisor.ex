defmodule Ace.TCP.Endpoint.Supervisor do
  use Supervisor

  def start_link(sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, [], sup_opts)
  end

  ## MODULE CALLBACKS

  def init(app) do
    children = [
      worker(Ace.TCP.Endpoint, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
