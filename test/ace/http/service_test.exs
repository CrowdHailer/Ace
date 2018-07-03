defmodule Ace.HTTP.ServiceTest do
  use ExUnit.Case, async: true

  @tag :skip
  test "service starts a new acceptor for each new connection" do
    {:ok, service} = Raxx.Forwarder.start_link(%{target: self()})

    {:ok, port} = Ace.HTTP.Service.port(service)

    {_socket, _worker_sup, server_sup, _governor_sup} = :sys.get_state(service)
    [first_child] = Supervisor.which_children(server_sup)

    {:ok, _client} =
      :ssl.connect(
        'localhost',
        port,
        mode: :binary,
        packet: :raw,
        active: false
      )

    Process.sleep(1000)
    [^first_child, _second_child] = Supervisor.which_children(server_sup)
  end

  test "governor will exit if server exits before accepting connection" do
    {:ok, service} = Raxx.Forwarder.start_link(%{target: self()})

    {:ok, _port} = Ace.HTTP.Service.port(service)

    {_socket, _worker_sup, server_sup, governor_sup} = :sys.get_state(service)
    [{_name, first_governor, _type, _args}] = Supervisor.which_children(governor_sup)
    [{_name, first_server, _type, _args}] = Supervisor.which_children(server_sup)

    monitor = Process.monitor(first_governor)
    Process.exit(first_server, :abnormal)

    assert_receive {:DOWN, ^monitor, :process, _pid, :abnormal}, 1000
  end

  test "governor will not exit if server exits after accepting connection" do
    # Just call `Ace.HTTP.Service.init` an turn test
    {:ok, service} = Raxx.Forwarder.start_link(%{target: self()})

    {:ok, port} = Ace.HTTP.Service.port(service)

    {_socket, _worker_sup, server_sup, governor_sup} = :sys.get_state(service)
    [{_name, first_governor, _type, _args}] = Supervisor.which_children(governor_sup)
    [{_name, first_server, _type, _args}] = Supervisor.which_children(server_sup)

    Process.monitor(first_governor)

    {:ok, _client} =
      :ssl.connect(
        'localhost',
        port,
        mode: :binary,
        packet: :raw,
        active: false
      )

    Process.sleep(100)

    Process.exit(first_server, :abnormal)

    assert Process.alive?(first_governor)
  end
end
