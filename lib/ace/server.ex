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

  @typedoc """
  The configuration used to start each server.

  A server configuration consists of behaviour, the `module`, and state.
  The module should implement the `Ace.Application` behaviour.
  Any value can be passed as the state.
  """
  @type app :: {module, state}

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
  @spec start_link(app) :: GenServer.on_start
  def start_link({application, config}) do
    GenServer.start_link(__MODULE__, {application, config}, [])
  end

  @doc """
  Manage a client connect with server

  Accept can only be called once for each server.
  After a connection has been closed the server will terminate.
  """
  @spec accept_connection(server, {:tcp, :inet.socket}) :: {:ok, reference} when
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

  def handle_call({:accept, socket}, from = {pid, _ref}, {:initialized, {mod, state}}) do
    connection_ref = make_ref()
    GenServer.reply(from, {:ok, connection_ref})
    {:ok, connection} = Connection.accept(socket)
    # Accept connection and send connection information to governer.
    connection_info = Connection.information(connection)
    send(pid, connection_ack(connection_ref, connection_info))
      # Handle the application response by sending any message and deciding the next step behaviour.
    mod.handle_connect(connection_info, state)
    |> next(mod, connection)
  end

  def handle_info({transport, _, packet}, {:connected, {mod, state}, connection}) when transport in [:tcp, :ssl] do
    # For any incoming tcp packet call the `handle_packet` action.
    mod.handle_packet(packet, state)
    |> next(mod, connection)
  end
  def handle_info({transport, _socket}, {:connected, {mod, state}, _connection}) when transport in [:tcp_closed, :ssl_closed] do
    # If the socket is closed call the `handle_disconnect` action.
    mod.handle_disconnect(transport, state)
    |> case do
      :ok ->
        {:stop, :normal, state}
    end
  end
  def handle_info(message, {:connected, {mod, state}, connection}) do
    # For any incoming erlang message the `handle_info` action.
    mod.handle_info(message, state)
    |> next(mod, connection)
  end

  defp next({:send, packet, state}, mod, connection) do
    # Set the socket to send a single received packet as a message to this process.
    # This stops the mailbox getting flooded but also also the server to respond to non tcp messages, this was not possible `using gen_tcp.recv`.
    :ok = Connection.send(connection, packet)
    :ok = Connection.set_active(connection, :once)
    {:noreply, {:connected, {mod, state}, connection}}
  end
  defp next({:send, packet, state, timeout}, mod, connection) do
    :ok = Connection.send(connection, packet)
    :ok = Connection.set_active(connection, :once)
    {:noreply, {:connected, {mod, state}, connection}, timeout}
  end
  defp next({:nosend, state}, mod, connection) do
    :ok = Connection.set_active(connection, :once)
    {:noreply, {:connected, {mod, state}, connection}}
  end
  defp next({:nosend, state, timeout}, mod, connection) do
    :ok = Connection.set_active(connection, :once)
    {:noreply, {:connected, {mod, state}, connection}, timeout}
  end
  defp next({:close, state}, mod, connection) do
    :ok = Connection.close(connection)
    {:stop, :normal, {mod, state}}
  end
end
