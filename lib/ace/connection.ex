defmodule Ace.Connection do
  @typedoc """
  Connection transport type.

  Options:
  - :tcp
  - :tls
  """
  @type transport :: :tcp | :tls

  @typedoc """
  Details of a servers connection with a client.
  """
  @type information :: %{
    peer: {:inet.ip_address, :inet.port_number},
    transport: transport
  }

  @typedoc """
  Generic client connection from either tcp or tls socket.
  """
  @type connection :: {:tcp, :inet.socket} | {:tls, :ssl.socket}

  @spec accept(connection) :: {:ok, connection}
  def accept({:tcp, socket}) do
    case :gen_tcp.accept(socket) do
      {:ok, connection} ->
        {:ok, {:tcp, connection}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def accept({:tls, socket}) do
    case :ssl.transport_accept(socket) do
      {:ok, socket} ->
        case :ssl.ssl_accept(socket) do
          :ok ->
            {:ok, {:tls, socket}}
          {:error, :closed} ->
            {:error, :econnaborted}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec information(connection) :: information
  def information({:tcp, connection}) do
    {:ok, peername} = :inet.peername(connection)
    %{peer: peername, transport: :tcp}
  end
  def information({:tls, connection}) do
    {:ok, peername} = :ssl.peername(connection)
    %{peer: peername, transport: :tls}
  end

  def port({:tcp, connection}) do
    :inet.port(connection)
  end
  def port({:tls, connection}) do
    {:ok, {_, port}} = :ssl.sockname(connection)
    {:ok, port}
  end

  def set_active({:tcp, connection}, :once) do
    :inet.setopts(connection, active: :once)
  end
  def set_active({:tls, connection}, :once) do
    :ssl.setopts(connection, active: :once)
  end

  def send({:tcp, connection}, message) do
    :gen_tcp.send(connection, message)
  end
  def send({:tls, connection}, message) do
    :ssl.send(connection, message)
  end

  def close({:tcp, connection}) do
    :gen_tcp.close(connection)
  end
  def close({:tls, connection}) do
    :ssl.close(connection)
  end
end
