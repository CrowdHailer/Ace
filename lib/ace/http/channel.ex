defmodule Ace.HTTP.Channel do
  @enforce_keys [
    :endpoint,
    :id,
    :socket
  ]

  defstruct @enforce_keys

  def monitor_endpoint(%__MODULE__{endpoint: endpoint}) do
    Process.monitor(endpoint)
  end

  def send(channel, parts)

  def send(channel, []) do
    {:ok, channel}
  end

  def send(channel = %__MODULE__{}, parts) do
    GenServer.call(channel.endpoint, {:send, channel, parts})
  end
end
