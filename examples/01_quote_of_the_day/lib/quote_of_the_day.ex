defmodule QuoteOfTheDay do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Ace.TCP, [{__MODULE__, []}, [port: 17]])
    ]

    opts = [strategy: :one_for_one, name: QuoteOfTheDay.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def init(conn, state) do
    {:send, "The future is here, just unevenly distributed", state}
  end
end
