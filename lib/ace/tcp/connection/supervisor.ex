defmodule Ace.TCP.Connection.Supervisor do
  use Supervisor

  def start_link(handler, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, handler, sup_opts)
  end

  # MODULE CALLBACKS

  def init(handler) do
    children = [
      worker(Ace.TCP.Connection, [handler], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
