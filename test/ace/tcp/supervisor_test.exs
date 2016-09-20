defmodule Ace.TCP.SupervisorTest do
  use ExUnit.Case, async: true

  test "stuff" do
    IO.inspect("starting")
    port = 8080
    {:ok, supervisor} = Ace.TCP.Supervisor.start_link(port: port)
    # Allow A/B testing
    {:ok, conn} = Supervisor.start_child(supervisor, [{Echo, :no_env}])
    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client_socket, "blob")
    {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)
    :ok = :gen_tcp.send(client_socket, "blob2")
    {:ok, "blob2"} = :gen_tcp.recv(client_socket, 0)
  end
end
