defmodule Ace.Connection do
  def accept({:tcp, socket}) do
    case :gen_tcp.accept(socket) do
      {:ok, connection} ->
        {:ok, {:tcp, connection}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def information({:tcp, connection}) do
    {:ok, peername} = :inet.peername(connection)
    %{peer: peername, transport: :tcp}
  end

  def send({:tcp, connection}, message) do
    :ok = :gen_tcp.send(connection, message)
  end
end
