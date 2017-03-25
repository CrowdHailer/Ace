defmodule Ace.Server do
  use GenServer
  alias Ace.Connection

  defmacro connection_ack(ref, conn) do
    quote do
      {unquote(__MODULE__), unquote(ref), unquote(conn)}
    end
  end

  def start_link(application, config) do
    GenServer.start_link(__MODULE__, {application, config}, [])
  end

  def accept_connection(server, socket) do
    GenServer.call(server, {:accept, socket})
  end

  def await_connection(server, socket) do
    {:ok, ref} = accept_connection(server, socket)
    # TODO link
    await_connection(ref)
  end
  def await_connection(ref) do
    receive do
      connection_ack(^ref, connection_info) ->
        {:ok, connection_info}
    end
  end

  def init(state) do
    {:ok, {:initialized, state}}
  end

  def handle_call({:accept, socket}, from = {pid, _ref}, {:initialized, app}) do
    connection_ref = make_ref()
    GenServer.reply(from, {:ok, connection_ref})
    case Connection.accept(socket) do
      {:ok, connection} ->
        connection_info = Connection.information(connection)
        send(pid, connection_ack(connection_ref, connection_info))
        {mod, state} = app
        mod.handle_connect(connection_info, state)
        |> case do
          {:send, packet, state} ->
            :ok = Connection.send(connection, packet)
            :ok = :inet.setopts(connection |> elem(1), active: :once)
            {:noreply, {:connected, {mod, state}, connection}}
          {:nosend, state} ->
            :ok = :inet.setopts(connection |> elem(1), active: :once)
            {:noreply, {:connected, {mod, state}, connection}}
        end
      {:error, :closed} ->
        exit(:normal)
    end
  end

  def handle_info({:tcp, _, packet}, {:connected, {mod, state}, connection}) do
    mod.handle_packet(packet, state)
    |> case do
      {:send, packet, state} ->
        :ok = Connection.send(connection, packet)
        :ok = :inet.setopts(connection |> elem(1), active: :once)
        {:noreply, {:connected, {mod, state}, connection}}
    end
  end
  def handle_info({:tcp_closed, socket}, {:connected, {mod, state}, connection}) do
    mod.handle_disconnect(:tcp_closed, state)
    |> case do
      :ok ->
        {:stop, :normal, state}
    end
  end
  def handle_info(message, {:connected, {mod, state}, connection}) do
    case mod.handle_info(message, state) do
      {:send, packet, state} ->
        :ok = Connection.send(connection, packet)
        :ok = :inet.setopts(connection |> elem(1), active: :once)
        {:noreply, {:connected, {mod, state}, connection}}
      {:nosend, state} ->
        :ok = :inet.setopts(connection |> elem(1), active: :once)
        {:noreply, {:connected, {mod, state}, connection}}
    end
  end


end
