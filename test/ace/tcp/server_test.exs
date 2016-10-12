defmodule Ace.TCPTest do
  use ExUnit.Case, async: true

  test "server process dies when socket is closed" do
    port = 10_004
    {:ok, listen_socket} = :gen_tcp.listen(port, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, server} = Ace.TCP.Server.start_link({GreetingServer, "WELCOME"})
    Task.async(fn
      () ->
        Ace.TCP.Server.accept(server, listen_socket)
    end)
    :timer.sleep(50)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\r\n"} = :gen_tcp.recv(client, 0, 2000)
    :ok = :gen_tcp.close(client)
    :timer.sleep(50)
    # assert false == Supervisor.which_children(server)
    assert false == Process.alive?(server)
  end
end
