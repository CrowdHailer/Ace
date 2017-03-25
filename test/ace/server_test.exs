defmodule Ace.ServerTest do
  use ExUnit.Case

  defmodule TestApplication do

    def handle_connect(info, test) do
      send(test, info)
      {:nosend, test}
    end
    def handle_disconnect(info, test) do
      :ok
    end

    # def handle_packet(packet, state) do
    #
    # end
  end

  defmodule EchoServer do
    @behaviour Ace.Application
    def handle_connect(_, state) do
      {:nosend, state}
    end

    def handle_packet(inbound, state) do
      {:send, "ECHO: #{String.strip(inbound)}\n", state}
    end
  end

  require Ace.Server

  test "sends peer information on connect" do
    {:ok, server} = Ace.Server.start_link(TestApplication, self())
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert_receive Ace.Server.connection_ack(^ref, conn)
    assert_receive ^conn
  end

  test "echos each message" do
    {:ok, server} = Ace.Server.start_link(EchoServer, [])
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)
  end

  test "says welcome for new connection" do
    {:ok, server} = Ace.Server.start_link(GreetingServer, "WELCOME")
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\n"} = :gen_tcp.recv(client, 0, 2000)
  end

  test "socket broadcasts server notification" do
    {:ok, server} = Ace.Server.start_link(BroadcastServer, self())
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    receive do
      {:register, pid} ->
        send(pid, {:notify, "HELLO"})
      end
    assert {:ok, "HELLO\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "socket ignores debug messages" do
    {:ok, server} = Ace.Server.start_link(BroadcastServer, self())
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    receive do
      {:register, pid} ->
        send(pid, :debug)
    end
    assert {:error, :timeout} == :gen_tcp.recv(client, 0, 1000)
  end

  test "server exits when connection closes" do
    {:ok, server} = Ace.Server.start_link(TestApplication, self())
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert_receive Ace.Server.connection_ack(^ref, conn)
    assert_receive ^conn
    :timer.sleep(50)
    :ok = :gen_tcp.close(client)
    :timer.sleep(50)
    assert false == Process.alive?(server)
  end
end
