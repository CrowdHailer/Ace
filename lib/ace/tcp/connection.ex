defmodule Ace.TCP.Connection do
  use GenServer

  def start_link(handler, listen_socket) do
    GenServer.start_link(__MODULE__, {handler, listen_socket}, [])
  end

  def init({handler = {mod, env}, listen_socket}) do
    socket = case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        socket
    end
    case mod.init(socket, env) do
      {:send, greeting} ->
        :gen_tcp.send(socket, greeting)
      :nosend ->
        :ok
    end
    {:ok, {handler, socket}}
  end

  def handle_info({:tcp, port, packet}, state = {{mod, env}, socket}) do
    case mod.handle_packet(packet, env) do
      {:send, greeting} ->
        :gen_tcp.send(socket, greeting)
      :nosend ->
        :ok
    end
    {:noreply, state}
  end
  def handle_info(info, state = {{mod, env}, socket}) do
    case mod.handle_info(info, env) do
      {:send, broadcast} ->
        :gen_tcp.send(socket, broadcast)
      :nosend ->
        :ok
    end
    {:noreply, state}
  end
end
