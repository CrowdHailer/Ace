defmodule Ace.TCP.Server do


  @typedoc """
  Information about the servers connection to the client
  """
  @type connection :: %{peer: {:inet.ip_address, :inet.port_number}}

  @typedoc """
  The current state of an individual server process.
  """
  @type state :: term

  @typedoc """
  The configuration used to start each server.

  A server configuration consists of behaviour, the `module`, and state.
  The module should implement the `Ace.TCP.Server` behaviour.
  Any value can be passed as the state.
  """
  @type app :: {module, state}






  def handle_call({:accept, listen_socket}, _from, {:awaiting, {mod, state}}) do
    # Accept and incoming connection request on the listening socket.
    # :timer.sleep(1)
    {:ok, socket} = case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        {:ok, socket}
      {:error, :closed} ->
        exit(:normal)
    end

    # Gather required information from new connection.
    {:ok, peername} = :inet.peername(socket)

    # Initialise the server with the app secification.
    response = mod.init(%{peer: peername}, state)

    # Handle the application response by sending any message and deciding the next step behaviour.
    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:reply, :ok, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:reply, :ok, {{mod, new_state}, socket}, timeout}
      :close ->
        {:stop, :normal, new_state}
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
      :close ->
        {:stop, :normal, new_state}
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
      :close ->
        {:stop, :normal, new_state}
    end
  end

  defp send_response({:send, message, state}, socket) do
    :ok = :gen_tcp.send(socket, message)
    # Set the socket to send a single received packet as a message to this process.
    # This stops the mailbox getting flooded but also also the server to respond to non tcp messages, this was not possible `using gen_tcp.recv`.
    :ok = :inet.setopts(socket, active: :once)
    {state, :normal}
  end
  defp send_response({:send, message, state, timeout}, socket) do
    :ok = :gen_tcp.send(socket, message)
    :ok = :inet.setopts(socket, active: :once)
    {state, {:timeout, timeout}}
  end
  defp send_response({:nosend, state}, socket) do
    :ok = :inet.setopts(socket, active: :once)
    {state, :normal}
  end
  defp send_response({:nosend, state, timeout}, socket) do
    :ok = :inet.setopts(socket, active: :once)
    {state, {:timeout, timeout}}
  end
  defp send_response({:close, state}, socket) do
    :ok = :gen_tcp.close(socket)
    {state, :close}
  end
end
