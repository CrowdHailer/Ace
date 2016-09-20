
defmodule Ace.TCP.ConnectionTest do
  use ExUnit.Case, async: true

  test "echo server(started from supervisor) will reply to every packet" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [{:active, true}, :binary])
    {:ok, port} = :inet.port(listen_socket)

    {:ok, supervisor} = Ace.TCP.Connection.Supervisor.start_link({Echo, []})
    task = Task.async(fn () ->
      # TODO wrap as connection supervisor
      Supervisor.start_child(supervisor, [listen_socket])
    end)

    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    Task.await(task)
    :ok = :gen_tcp.send(client_socket, "blob")
    {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)
    :ok = :gen_tcp.send(client_socket, "blob2")
    {:ok, "blob2"} = :gen_tcp.recv(client_socket, 0)
  end

  test "echo server will reply to every packet" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [{:active, true}, :binary])
    {:ok, port} = :inet.port(listen_socket)

    task = Task.async(fn () ->
      Ace.TCP.Connection.start_link({Echo, []}, listen_socket)
    end)

    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    Task.await(task)
    :ok = :gen_tcp.send(client_socket, "blob")
    {:ok, "blob"} = :gen_tcp.recv(client_socket, 0)
    :ok = :gen_tcp.send(client_socket, "blob2")
    {:ok, "blob2"} = :gen_tcp.recv(client_socket, 0)
  end

  test "greeting server will welcome new connection" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [{:active, true}, :binary])
    {:ok, port} = :inet.port(listen_socket)

    task = Task.async(fn () ->
      Ace.TCP.Connection.start_link({Greet, "hello"}, listen_socket)
    end)

    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    Task.await(task)
    {:ok, "hello"} = :gen_tcp.recv(client_socket, 0)
  end

  test "broadcast server will send all information" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [{:active, true}, :binary])
    {:ok, port} = :inet.port(listen_socket)
    test_pid = self
    task = Task.async(fn () ->
      Ace.TCP.Connection.start_link({Broadcast, test_pid}, listen_socket)
    end)

    {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    Task.await(task)
    target = receive do
      {:register, target} ->
        target
    end
    send(target, "update")
    {:ok, "update"} = :gen_tcp.recv(client_socket, 0)
    send(target, "update2")
    {:ok, "update2"} = :gen_tcp.recv(client_socket, 0)
  end


end
