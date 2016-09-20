defmodule Ace do
  use Application

  def start(_type, _args) do
    # Ace.Supervisor.start_link
    {:ok, self}
  end
end
