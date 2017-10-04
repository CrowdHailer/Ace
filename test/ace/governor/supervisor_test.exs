defmodule Ace.Governor.SupervisorTest do
  use ExUnit.Case

  alias Ace.{Server, Governor, Connection}

  @socket_options mode: :binary, packet: :line, active: false, reuseaddr: true

  @tag :skip
  test "drain connection pool" do
    {:ok, server_supervisor} = Server.Supervisor.start_link({EchoServer, :explode})
    {:ok, socket} = :gen_tcp.listen(0, @socket_options)
    socket = {:tcp, socket}
    {:ok, port} = Connection.port(socket)

    {:ok, governor_supervisor} = Governor.Supervisor.start_link(server_supervisor, socket, 1)

    # Establish connection
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)

    # Drain connections
    :ok = Governor.Supervisor.drain(governor_supervisor)
    assert [] = Supervisor.which_children(governor_supervisor)
    assert [_1] = Supervisor.which_children(server_supervisor)

    # New connection not made
    {:ok, client2} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary], 100)
    :ok = :gen_tcp.send(client2, "blob\n")
    assert {:error, :timeout} = :gen_tcp.recv(client2, 0, 100)

    # Establish connection still available
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)
  end
end
