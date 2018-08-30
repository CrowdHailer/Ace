defmodule Ace.HTTP.Channel do
  @moduledoc """
  Reference to a single HTTP request/response exchange, within the context of a connection.

  - With HTTP/2 a channel corresponds to a single stream.
  - With HTTP/1.1 pipelining a single connection can support multiple channels.

  The channel struct provides a normalised structure regardless of which version of the protocol is used.
  A channel struct also contains all information about the connection.

  - TODO consider calling this exchange instead of channel.
  - TODO add functions like `cleartext?` `http_version?` `transport_version` that pull information from socket.
  """

  @type t :: %__MODULE__{
          endpoint: pid,
          id: integer,
          socket: Ace.Socket.t()
        }

  @enforce_keys [
    :endpoint,
    :id,
    :socket
  ]

  defstruct @enforce_keys

  @doc """
  Monitor the process managing the local endpoint of the connection containing a channel.
  """
  @spec monitor_endpoint(t()) :: reference()
  def monitor_endpoint(%__MODULE__{endpoint: endpoint}) do
    Process.monitor(endpoint)
  end

  @doc """
  Send a list of message parts over a HTTP channel.
  """
  @spec send(t(), [Raxx.part()]) :: {:ok, t()} | {:error, :connection_closed}
  def send(channel, parts)

  def send(channel, []) do
    {:ok, channel}
  end

  def send(channel = %__MODULE__{}, parts) do
    GenServer.call(channel.endpoint, {:send, channel, parts})
  catch
    # NOTE `GenServer.call` exits if the target process has already exited.
    # A connection closing will also stop workers (this process).
    # However this case can still occur due to race conditions.
    :exit, {:noproc, _} ->
      {:error, :connection_closed}
  end

  @doc """
  Send an acknowledgement that the `Ace.HTTP.Worker` has received a request part
  """
  @spec ack(t()) :: :ok
  def ack(channel = %__MODULE__{}) do
    Kernel.send(channel.endpoint, :ack)
    :ok
  end
end
