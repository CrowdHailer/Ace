defmodule Ace.TCP.AcceptorTest do
  use ExUnit.Case, async: true

  test "stuff" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [{:active, true}, :binary])
    {:ok, port} = :inet.port(listen_socket)

    {:ok, supervisor} = Ace.TCP.Connection.Supervisor.start_link({Echo, []})
    {:ok, acceptor} = Ace.TCP.Acceptor.start_link(listen_socket, supervisor)

    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client_socket, "blob")
    {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)

    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client_socket, "blob")
    {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)
  end
end
