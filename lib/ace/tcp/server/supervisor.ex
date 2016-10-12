defmodule Ace.TCP.Server.Supervisor do
  use Supervisor

  def start_link(app, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, app, sup_opts)
  end

  # MODULE CALLBACKS

  def init(app) do
    children = [
      worker(Ace.TCP.Server, [app], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
