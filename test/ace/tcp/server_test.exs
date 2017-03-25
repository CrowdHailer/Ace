defmodule Ace.TCP.ServerTest do
  use ExUnit.Case, async: true

  @tag :skip
  test "can respond by closing the connection" do
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, server} = Ace.TCP.Server.start_link({CloseIt, self()})

    Task.async(fn
      () ->
        Ace.TCP.Server.accept(server, listen_socket)
    end)
    :timer.sleep(50)

    {:ok, port} = :inet.port(listen_socket)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])

    assert true == Process.alive?(server)
    send(server, :close)

    assert {:error, :closed} = :gen_tcp.recv(client, 0, 1000)
    :timer.sleep(1000)
    assert false == Process.alive?(server)
  end
end
