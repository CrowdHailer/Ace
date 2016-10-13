defmodule MyServer do
  def init(_connection, state = {:greeting, greeting}) do
    {:send, greeting, state}
  end

  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\r\n", state}
  end

  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\r\n", state}
  end

  def terminate(_reason, _state) do
    IO.puts("Socket connection closed")
  end
end

defmodule Ace do
  use Application

  def start(_type, _args) do
    Ace.TCP.Endpoint.Supervisor.start_link(name: Ace.TCP.Endpoint.Supervisor)
  end

  def start_tcp(app, options) do
    Supervisor.start_child(Ace.TCP.Endpoint.Supervisor, [app, options])
  end
end
