defmodule Ace.GovernorTest do
  use ExUnit.Case

  alias Ace.{Server, Governor, Connection}

  @socket_options mode: :binary, packet: :line, active: false, reuseaddr: true

  @tag :skip
  test "governor starts new server when connection established" do
    {:ok, supervisor} = Server.Supervisor.start_link({EchoServer, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    socket = {:tcp, socket}
    {:ok, port} = Connection.port(socket)

    {:ok, _governor} = Governor.start_link(socket, supervisor)
    assert [first = {_name, _server, :worker, _args}] = Supervisor.which_children(supervisor)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)

    assert [^first, {_name, _server, :worker, _args}] = Supervisor.which_children(supervisor)
  end

  @tag :skip
  test "governor will exit if server exits before establishing connection" do
    Process.flag(:trap_exit, true)
    {:ok, supervisor} = Server.Supervisor.start_link({__MODULE__, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    socket = {:tcp, socket}

    {:ok, governor} = Governor.start_link(socket, supervisor)
    [{_name, server, :worker, _args}] = Supervisor.which_children(supervisor)
    Process.exit(server, :abnormal)
    assert_receive {:EXIT, ^governor, :abnormal}
  end

  def handle_connect(_, :normal) do
    exit(:normal)
  end

  @tag :skip
  test "governor will start new server that exits normally before establishing connection" do
    Process.flag(:trap_exit, true)
    {:ok, supervisor} = Server.Supervisor.start_link({__MODULE__, :normal})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    {:ok, port} = :inet.port(socket) # listen_socket
    socket = {:tcp, socket}

    {:ok, _governor} = Governor.start_link(socket, supervisor)
    [{_name, server1, :worker, _args}] = Supervisor.which_children(supervisor)
    ref = Process.monitor(server1)
    {:ok, _client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert_receive {:DOWN, ^ref, :process, ^server1, :normal}
    Process.sleep(1_000)
    [{_name, server2, :worker, _args}] = Supervisor.which_children(supervisor)
    assert server2 != server1
  end

  @tag :skip
  test "governor will exit if server fails to establish connection" do
    Process.flag(:trap_exit, true)
    {:ok, supervisor} = Server.Supervisor.start_link({__MODULE__, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    {:ok, port} = :inet.port(socket) # listen_socket
    socket = {:tcp, socket}

    {:ok, governor} = Governor.start_link(socket, supervisor)
    {:ok, _client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert_receive {:EXIT, ^governor, {:function_clause, _}}
  end

  @tag :skip
  test "governor will not exit if server exits after establishing connection" do
    Process.flag(:trap_exit, true)
    {:ok, supervisor} = Server.Supervisor.start_link({EchoServer, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    socket = {:tcp, socket}
    {:ok, port} = Connection.port(socket)

    {:ok, _governor} = Governor.start_link(socket, supervisor)
    [{_name, server, :worker, _args}] = Supervisor.which_children(supervisor)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)

    Process.sleep(500)

    Process.exit(server, :abnormal)
    # Do not receive any message exit or monitor.
    refute_receive _
  end
end
