defmodule Ace do
  use Application

  def start(_type, _args) do
    Ace.TCP.Endpoint.Supervisor.start_link(name: Ace.TCP.Endpoint.Supervisor)
  end

  def start_tcp(app, options) do
    Supervisor.start_child(Ace.TCP.Endpoint.Supervisor, [app, options])
  end
end
