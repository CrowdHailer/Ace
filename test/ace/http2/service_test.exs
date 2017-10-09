defmodule Ace.HTTP2.ServiceTest do
  use ExUnit.Case

  alias Ace.HTTP.Service

  test "service can be started as named process" do
    opts = [port: 0, certfile: Support.test_certfile(), keyfile: Support.test_keyfile(), name: __MODULE__]
    assert {:ok, pid} = Service.start_link({Raxx.Forwarder, %{test: self()}}, opts)
    assert pid == Process.whereis(__MODULE__)
  end
end
