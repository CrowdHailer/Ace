defmodule CounterServer do
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

  def terminate(_, _) do
    :ok
  end
end

defmodule GreetingServer do
  def init(_, message) do
    {:send, "#{message}\r\n", []}
  end

  def terminate(_reason, _state) do
    IO.puts("Socket connection closed")
  end
end

defmodule EchoServer do
  def init(_, state) do
    {:nosend, state}
  end

  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\r\n", state}
  end
end

defmodule BroadcastServer do
  def init(_, pid) do
    send(pid, {:register, self})
    {:nosend, pid}
  end

  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\r\n", state}
  end
end

defmodule Ace.TCPTest do
  use ExUnit.Case, async: true

  test "echos each message" do
    port = 10001
    {:ok, _server} = Ace.TCP.start(port, {EchoServer, []})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\r\n")
    assert {:ok, "ECHO: blob\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "says welcome for new connection" do
    port = 10002
    {:ok, _server} = Ace.TCP.start(port, {GreetingServer, "WELCOME"})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\r\n"} = :gen_tcp.recv(client, 0, 2000)
  end

  test "socket broadcasts server message" do
    port = 10_003
    {:ok, _server} = Ace.TCP.start(port, {BroadcastServer, self})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    receive do
      {:register, pid} ->
        send(pid, {:notify, "HELLO"})
      end
    assert {:ok, "HELLO\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "state is passed through messages" do
    port = 10_004
    {:ok, _server} = Ace.TCP.start(port, {CounterServer, 0})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client, 0)
    :ok = :gen_tcp.send(client, "anything\r\n")
    assert {:ok, "2\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "start multiple connections" do
    port = 10_005
    {:ok, _endpoint} = Ace.TCP.start(port, {CounterServer, 0})
    {:ok, client1} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, client2} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client1, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client1, 0)
    :ok = :gen_tcp.send(client2, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client2, 0)
  end

  test "scratch" do
    me = self()
    t = Task.async fn () ->
      {:ok, s} = :gen_tcp.listen(8090, mode: :binary)
      :erlang.process_flag(:trap_exit, true)
      Process.link(s) |> IO.inspect
      send(me, {:lsock, s})
      :timer.sleep(500)
      receive do
        s -> s |> IO.inspect
      end
    end
    lsock = receive do
      {:lsock, s} ->
        s
    end
    Process.link(lsock) |> IO.inspect
    :gen_tcp.listen(8090, mode: :binary) |> IO.inspect

    IEx.Info.Port.info(lsock) |> IO.inspect
    :timer.sleep(1000)
    :gen_tcp.close(lsock)
    |> IO.inspect
    IEx.Info.Port.info(lsock) |> IO.inspect
    assert {_, ^lsock, _} = Task.await(t)
  end
end
