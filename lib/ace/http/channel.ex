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
  # TODO raxx.part type
  @spec send(t(), [Raxx.Request.t() | Raxx.Response.t() | Raxx.Data.t() | Raxx.Tail.t()]) ::
          {:ok, t()}
  def send(channel, parts)

  def send(channel, []) do
    {:ok, channel}
  end

  def send(channel = %__MODULE__{}, parts) do
    GenServer.call(channel.endpoint, {:send, channel, parts})
  end
end
