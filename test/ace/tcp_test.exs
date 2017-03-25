defmodule Ace.TCP.EndpointTest do
  use ExUnit.Case, async: true

  test "start multiple connections" do
    {:ok, endpoint} = Ace.TCP.start_link({CounterServer, 0}, port: 0)
    {:ok, port} = Ace.TCP.port(endpoint)
    {:ok, client1} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, client2} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client1, "TOTAL\r\n")
    assert {:ok, "0\r\n"} = :gen_tcp.recv(client1, 0)
    :ok = :gen_tcp.send(client2, "TOTAL\r\n")
    assert {:ok, "0\r\n"} = :gen_tcp.recv(client2, 0)
  end

  test "will register the new enpoint with the given name" do
    {:ok, endpoint} = Ace.TCP.start_link({EchoServer, []}, port: 0, name: NamedEndpoint)
    assert endpoint == Process.whereis(NamedEndpoint)
  end

  test "there are n servers accepting at any given time" do
    {:ok, endpoint} = Ace.TCP.start_link({EchoServer, []}, port: 0, acceptors: 10)
    {_, _, governor_supervisor} = :sys.get_state(endpoint)
    assert %{active: 10} = Supervisor.count_children(governor_supervisor)
  end

end
