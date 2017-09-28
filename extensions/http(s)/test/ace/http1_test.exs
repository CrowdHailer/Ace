defmodule Ace.HTTP1Test do
  use ExUnit.Case

  import ExUnit.CaptureLog, only: [capture_log: 1]

  setup do
    raxx_app = {Raxx.Forwarder, %{test: self()}}
    capture_log fn() ->
      {:ok, endpoint} = Ace.HTTP.start_link(raxx_app, port: 0)
      {:ok, port} = Ace.HTTP.port(endpoint)
      send(self(), {:port, port})
    end
    port = receive do
      {:port, port} -> port
    end
    {:ok, %{port: port}}
  end

  @tag :skip
  # DEBT add when transfer_encoding supported
  test "transfer_encoding not supported", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    transfer-encoding: chunked

    """
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

  end
end
