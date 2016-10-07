defmodule Counter do
  def init(_, num) do
    {:nosend, num}
  end

  def handle_packet(_, last) do
    count = last + 1
    {:send, "#{count}\r\n", count}
  end

  def handle_info(_, last) do
    {:nosend, last}
  end
end

defmodule Ace.TCPTest do
  use ExUnit.Case, async: true

  test "echos each message" do
    port = 10001
    {:ok, server} = Ace.TCP.start(port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, _welcome_message} = :gen_tcp.recv(client, 0)
    :ok = :gen_tcp.send(client, "blob\r\n")
    assert {:ok, "ECHO: blob\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "says welcome for new connection" do
    port = 10002
    {:ok, server} = Ace.TCP.start(port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\r\n"} = :gen_tcp.recv(client, 0, 2000)
  end

  test "socket broadcasts server message" do
    port = 10_003
    {:ok, server} = Ace.TCP.start(port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, _welcome_message} = :gen_tcp.recv(client, 0, 2000)
    send(server, {:data, "HELLO"})
    assert {:ok, "HELLO\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "process for closed socket has died" do
    port = 10_004
    {:ok, server} = Ace.TCP.start(port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\r\n"} = :gen_tcp.recv(client, 0, 2000)
    :ok = :gen_tcp.close(client)
    :timer.sleep(50)
    assert false == Process.alive?(server)
  end

  test "state is passed through messages" do
    port = 10_004
    {:ok, server} = Ace.TCP.start(port, {Counter, 0})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client, 0)
    :ok = :gen_tcp.send(client, "anything\r\n")
    assert {:ok, "2\r\n"} = :gen_tcp.recv(client, 0)
  end
end
