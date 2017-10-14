defmodule Ace.HTTP2.ConnectionTest do
  use ExUnit.Case

  alias Ace.HTTP2.{Service, Client}

  test "failure to start client forwards error" do
    # TODO Should their be an exit signal for failure to start
    # How do standard supervisors handle this
    Process.flag(:trap_exit, true)
    assert {:error, :nxdomain} = Client.start_link({'nohost', 443})
  end

  test "client exits normally for lost connection" do
    opts = [
      port: 0,
      owner: self(),
      certfile: Support.test_certfile(),
      keyfile: Support.test_keyfile()
    ]

    assert {:ok, service} = Service.start_link({Raxx.Forwarder, %{test: self()}}, opts)
    assert_receive {:listening, ^service, port}

    {:ok, client} = Client.start_link({'localhost', port})
    ref = Process.monitor(client)
    Process.exit(service, :normal)
    assert_receive {:DOWN, ^ref, :process, ^client, :normal}, 5000
  end
end
