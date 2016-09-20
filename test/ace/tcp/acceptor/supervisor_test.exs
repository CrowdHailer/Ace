defmodule Ace.TCP.Acceptor.SupervisorTest do
  use ExUnit.Case, async: true

  @tag :skip
  test "stuff" do
    port = 8081
    {:ok, supervisor} = Ace.TCP.Acceptor.Supervisor.start_link(port: port)
    Supervisor.count_children(supervisor)
    |> IO.inspect
    # # Allow A/B testing
    # {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    # :ok = :gen_tcp.send(client_socket, "blob")
    # {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)
    # :ok = :gen_tcp.send(client_socket, "blob2")
    # {:ok, "blob2"} = :gen_tcp.recv(client_socket, 0)
  end
end
