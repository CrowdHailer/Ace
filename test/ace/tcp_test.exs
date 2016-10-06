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
    port = 10_004
    {:ok, server} = Ace.TCP.start(port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, _welcome_message} = :gen_tcp.recv(client, 0, 2000)
    send(server, {:data, "HELLO"})
    assert {:ok, "HELLO\r\n"} = :gen_tcp.recv(client, 0)
  end
end
