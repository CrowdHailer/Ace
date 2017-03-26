defmodule QuoteOfTheDay do
  use Application
  use Ace.Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Ace.TCP, [{__MODULE__, []}, [port: 17, name: QuoteOfTheDay.TCP, acceptors: 5]])
    ]

    opts = [strategy: :one_for_one, name: QuoteOfTheDay.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def handle_connect(conn = %{peer: peer}, _state) do
    {{a,b,c,d}, port} = peer
    IO.puts("Socket connection opened from #{a}.#{b}.#{c}.#{d}:#{port}")
    {:send, "The future is here, just unevenly distributed\r\n", conn}
  end

  def handle_packet(_, state) do
    {:nosend, state}
  end

  def handle_info(_, state) do
    {:nosend, state}
  end

  def handle_disconnect(_, _) do
    :ok
  end

  def terminate(_reason, %{peer: peer}) do
    {{a,b,c,d}, port} = peer
    IO.puts("Socket connection closed from #{a}.#{b}.#{c}.#{d}:#{port}")
  end
end
