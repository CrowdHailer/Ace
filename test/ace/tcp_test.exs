defmodule Echo do
  def init(_socket, :no_env) do
    :nosend
  end

  def handle_packet(packet, _env) do
    {:send, packet}
  end

  def handle_info(_update, _env) do
    :nosend
  end
end

defmodule Greet do
  def init(_socket, message) do
    {:send, message}
  end

  def handle_packet(_packet, _env) do
    :nosend
  end

  def handle_info(_update, _env) do
    :nosend
  end
end

defmodule Broadcast do
  def init(_socket, pid) do
    send(pid, {:register, self()})
    :nosend
  end

  def handle_packet(_packet, _pid) do
    :nosend
  end

  def handle_info(update, _pid) do
    {:send, update}
  end

end

defmodule Ace.TCPTest do
  use ExUnit.Case, async: true

  test "echo server will reply to every packet" do
    {:ok, server} = Ace.TCP.start_server(Echo, port: 0)
    {:ok, port} = Ace.TCP.read_port(server)
    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client_socket, "blob")
    {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)
    :ok = :gen_tcp.send(client_socket, "blob2")
    {:ok, "blob2"} = :gen_tcp.recv(client_socket, 0)
  end

  test "greeting server will welcome new connection" do
    {:ok, server} = Ace.TCP.start_server({Greet, "hello"}, port: 0)
    {:ok, port} = Ace.TCP.read_port(server)
    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, "hello"} = :gen_tcp.recv(client_socket, 0)
  end

  test "broadcast server will send all information" do
    {:ok, server} = Ace.TCP.start_server({Broadcast, self()}, port: 0)
    {:ok, port} = Ace.TCP.read_port(server)
    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    target = receive do
      {:register, target} ->
        target
    end
    send(target, "update")
    {:ok, "update"} = :gen_tcp.recv(client_socket, 0)
    send(target, "update2")
    {:ok, "update2"} = :gen_tcp.recv(client_socket, 0)
  end


end
