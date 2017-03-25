defmodule Ace.Server do
  @moduledoc """
  `#{__MODULE__}` manages a single client connection.

  A server is started with an module to define behaviour and configuration as initial state.

  See the README.md for a complete overview on how to make a server available.

  *The server process accepts as well as manages the connection.
  There is no separate acceptor process.
  This means that that is no need to switch the connections owning process.
  Several erlang servers do use separate acceptor pools.*
  """

  @typedoc """
  The current state of an individual server process.
  """
  @type state :: term

  use GenServer
  alias Ace.Connection

  defmacro connection_ack(ref, conn) do
    quote do
      {unquote(__MODULE__), unquote(ref), unquote(conn)}
    end
  end

  @doc """
  Start a new `#{__MODULE__}` linked to the calling process.

  A server is started with an app to describe its behaviour and configuration for initial state.

  The server process is returned immediatly.
  This is allow a supervisor to start several servers without waiting for connections.

  To accept a connection `accept_connection/2` must be called.

  A provisioned server will remain in an awaiting state until accept is called.
  """
  @spec start_link(module, state) :: GenServer.on_start
  def start_link(application, config) do
    GenServer.start_link(__MODULE__, {application, config}, [])
  end

  @doc """
  Manage a client connect with server

  Accept can only be called once for each server.
  After a connection has been closed the server will terminate.
  """
  @spec accept_connection(server, :inet.socket) :: :ok when
    server: pid
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

  ## Server callbacks

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
        |> next(mod, connection)
      {:error, :closed} ->
        exit(:normal)
    end
  end

  def handle_info({:tcp, _, packet}, {:connected, {mod, state}, connection}) do
    mod.handle_packet(packet, state)
    |> next(mod, connection)
  end
  def handle_info({:tcp_closed, socket}, {:connected, {mod, state}, connection}) do
    mod.handle_disconnect(:tcp_closed, state)
    |> case do
      :ok ->
        {:stop, :normal, state}
    end
  end
  def handle_info(message, {:connected, {mod, state}, connection}) do
    mod.handle_info(message, state)
    |> next(mod, connection)
  end

  defp next({:send, packet, state}, mod, connection) do
    :ok = Connection.send(connection, packet)
    :ok = :inet.setopts(connection |> elem(1), active: :once)
    {:noreply, {:connected, {mod, state}, connection}}
  end
  defp next({:send, packet, state, timeout}, mod, connection) do
    :ok = Connection.send(connection, packet)
    :ok = :inet.setopts(connection |> elem(1), active: :once)
    {:noreply, {:connected, {mod, state}, connection}, timeout}
  end
  defp next({:nosend, state}, mod, connection) do
    :ok = :inet.setopts(connection |> elem(1), active: :once)
    {:noreply, {:connected, {mod, state}, connection}}
  end
  defp next({:nosend, state, timeout}, mod, connection) do
    :ok = :inet.setopts(connection |> elem(1), active: :once)
    {:noreply, {:connected, {mod, state}, connection}, timeout}
  end
end
