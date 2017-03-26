defmodule Ace.Connection do
  @typedoc """
  Connection transport type.

  Options:
  - :tcp
  """
  @type transport :: :tcp

  @typedoc """
  Details of a servers connection with a client.
  """
  @type information :: %{
    peer: {:inet.ip_address, :inet.port_number},
    transport: transport
  }

  @type connection :: {:tcp, :inet.socket}

  def accept({:tcp, socket}) do
    case :gen_tcp.accept(socket) do
      {:ok, connection} ->
        {:ok, {:tcp, connection}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec information(connection) :: information
  def information({:tcp, connection}) do
    {:ok, peername} = :inet.peername(connection)
    %{peer: peername, transport: :tcp}
  end

  def set_active({:tcp, connection}, :once) do
    :inet.setopts(connection, active: :once)
  end

  def send({:tcp, connection}, message) do
    :gen_tcp.send(connection, message)
  end

  def close({:tcp, connection}) do
    :gen_tcp.close(connection)
  end
end
