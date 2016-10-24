defmodule Ace.TCP.Server do
  @moduledoc """
  Each `Ace.TCP.Server` manages a single TCP connection.
  They are responsible for managing communication between a TCP client and the larger application.

  The server process accepts as well as manages the connection.
  There is no separate acceptor process.
  This means that that is no need to switch the connections owning process.
  Several erlang servers do use separate acceptor pools.

  ## Example

  The TCP.Server abstracts the common code required to manage a TCP connection.
  Developers only need to their own Server module to define app specific behaviour.

  ```elixir
  defmodule CounterServer do
    def init(_, num) do
      {:nosend, num}
    end

    def handle_packet(_, last) do
      count = last + 1
      {:send, "\#{count}\r\n", count}
    end

    def handle_info(_, last) do
      {:nosend, last}
    end
  end
  ```
  """

  # Use OTP behaviour so the server can be added to a supervision tree.
  use GenServer

  # Alias erlang libraries so the following code is more readable.

  # Interface to TCP/IP sockets.
  alias :gen_tcp, as: TCP

  # Helpers for the TCP/IP protocols.
  alias :inet, as: Inet

  @doc """
  Start a new `Ace.TCP.Server` linked to the calling process.

  A server process is started with an app to describe handling connections.
  The app is a comination of behaviour and state `app = {module, config}`

  The server process is returned immediatly.
  This is allow a supervisor to start several servers without waiting for connections.

  A provisioned server will remain in an awaiting state untill accept is called.
  """
  def start_link(app) do
    GenServer.start_link(__MODULE__, {:app, app}, [])
  end

  @doc """
  Take provisioned server to accept the next connection on a socket.

  Accept can only be called once for each server.
  After a connection has been closed the server will terminate.
  """
  def accept(server, listen_socket) do
    GenServer.call(server, {:accept, listen_socket}, :infinity)
  end

  ## Server callbacks

  def init({:app, app}) do
    {:ok, {:awaiting, app}}
  end

  def handle_call({:accept, listen_socket}, _from, {:awaiting, {mod, state}}) do
    # Accept and incoming connection request on the listening socket.
    # :timer.sleep(1)
    {:ok, socket} = case TCP.accept(listen_socket) do
      {:ok, socket} ->
        {:ok, socket}
      {:error, :closed} ->
        exit(:normal)
    end

    # Gather required information from new connection.
    {:ok, peername} = Inet.peername(socket)

    # Initialise the server with the app secification.
    response = mod.init(%{peer: peername}, state)

    # Handle the application response by sending any message and deciding the next step behaviour.
    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:reply, :ok, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:reply, :ok, {{mod, new_state}, socket}, timeout}
    end
  end


  def handle_info({:tcp, socket, packet}, {{mod, state}, socket}) do
    # For any incoming tcp packet call the `handle_packet` action.
    response = mod.handle_packet(packet, state)

    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:noreply, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:noreply, {{mod, new_state}, socket}, timeout}
    end
  end
  def handle_info({:tcp_closed, socket}, {{mod, state}, socket}) do
    # If the socket is closed call the `terminate` action.
    case mod.terminate(:tcp_closed, state) do
      :ok ->
        # FIXME it's normal for sockets to close, might want termination callback to return reason.
        {:stop, :normal, state}
    end
  end
  def handle_info(message, {{mod, state}, socket}) do
    # For any incoming erlang message the `handle_info` action.
    response = mod.handle_info(message, state)

    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:noreply, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:noreply, {{mod, new_state}, socket}, timeout}
    end
  end

  defp send_response({:send, message, state}, socket) do
    :ok = TCP.send(socket, message)
    # Set the socket to send a single received packet as a message to this process.
    # This stops the mailbox getting flooded but also also the server to respond to non tcp messages, this was not possible `using gen_tcp.recv`.
    :ok = Inet.setopts(socket, active: :once)
    {state, :normal}
  end
  defp send_response({:send, message, state, timeout}, socket) do
    :ok = TCP.send(socket, message)
    :ok = Inet.setopts(socket, active: :once)
    {state, {:timeout, timeout}}
  end
  defp send_response({:nosend, state}, socket) do
    :ok = Inet.setopts(socket, active: :once)
    {state, :normal}
  end
  defp send_response({:nosend, state, timeout}, socket) do
    :ok = Inet.setopts(socket, active: :once)
    {state, {:timeout, timeout}}
  end
end
