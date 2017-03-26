defmodule Ace.GovernorTest do
  use ExUnit.Case

  alias Ace.{Server, Governor, Connection}

  @socket_options mode: :binary, packet: :line, active: false, reuseaddr: true

  test "governor starts new server when connection established" do
    {:ok, supervisor} = Server.Supervisor.start_link({EchoServer, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    socket = {:tcp, socket}
    {:ok, port} = Connection.port(socket)

    {:ok, governor} = Governor.start_link(socket, supervisor)
    assert [first = {_name, server, :worker, _args}] = Supervisor.which_children(supervisor)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)

    assert [^first, {_name, _server, :worker, _args}] = Supervisor.which_children(supervisor)
  end

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

  test "governor will not exit if server exits after establishing connection" do
    Process.flag(:trap_exit, true)
    {:ok, supervisor} = Server.Supervisor.start_link({__MODULE__, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    socket = {:tcp, socket}
    {:ok, port} = Connection.port(socket)

    {:ok, governor} = Governor.start_link(socket, supervisor)
    [{_name, server, :worker, _args}] = Supervisor.which_children(supervisor)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])

    Process.exit(server, :abnormal)
    refute_receive {:EXIT, ^governor, :abnormal}
  end
end
