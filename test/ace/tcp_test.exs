defmodule Ace.TCPTest do
  use ExUnit.Case, async: true

  test "echos each message" do
    port = 10001

    # Starting a server does not return until a connection has been dealt with.
    # For this reason the call needs to be in a separate process.
    # FIXME have the `start` call complete when the server is ready to accept a connection.
    task = Task.async(fn () ->
      {:ok, server} = Ace.TCP.start(port)
    end)
    :timer.sleep(100)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, _welcome_message} = :gen_tcp.recv(client, 0)
    :ok = :gen_tcp.send(client, "blob\r\n")
    assert {:ok, "ECHO: blob\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "says welcome for new connection" do
    port = 10002

    task = Task.async(fn () ->
      {:ok, server} = Ace.TCP.start(port)
    end)
    :timer.sleep(100)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\r\n"} = :gen_tcp.recv(client, 0, 2000)
  end
end
