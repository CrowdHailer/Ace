defmodule Ace.HTTP.ConnectionTest do
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

  test "connection is closed at clients request for HTTP 1.1 request", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com
    connection: close
    x-test: Value

    """
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, _state}}, 1_000
    GenServer.reply(from, Raxx.response(:no_content))

    assert request.headers == [{"x-test", "Value"}]
    assert_receive {:tcp, ^socket, response}, 1_000
    assert response == "HTTP/1.1 204 No Content\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:tcp_closed, ^socket}, 1_000
  end

  # DEBT implement HTTP/1.1 pipelining
  test "connection is closed at clients even for keep_alive request", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com
    connection: keep-alive
    x-test: Value

    """
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, _state}}, 1_000
    GenServer.reply(from, Raxx.response(:no_content))

    assert request.headers == [{"x-test", "Value"}]
    assert_receive {:tcp, ^socket, response}, 1_000
    assert response == "HTTP/1.1 204 No Content\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:tcp_closed, ^socket}, 1_000
  end
end
