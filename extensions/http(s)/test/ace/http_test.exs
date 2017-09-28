defmodule Ace.HTTPTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog, only: [capture_log: 1]

  doctest Ace.HTTP

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

  test "400 response for invalid start_line", %{port: port} do
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, "rubbish\n")

    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:tcp_closed, ^connection}, 1_000
  end

  test "400 response for invalid headers", %{port: port} do
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, "GET / HTTP/1.1\r\na \r\n::\r\n")

    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:tcp_closed, ^connection}, 1_000
  end

  test "too long url ", %{port: port} do
    path = (for _i <- 1..3000, do: "a")
    |> Enum.join("")

    request = """
    GET /#{path} HTTP/1.1
    Host: www.raxx.com

    """
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, request)

    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 414 URI Too Long\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:tcp_closed, ^connection}, 1_000
  end

  test "Client too slow to deliver body", %{port: port} do
    unfinished_head = """
    GET / HTTP/1.1
    Host: www.raxx.com
    """
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, unfinished_head)
    assert_receive {:tcp, ^connection, response}, 15_000
    assert response == "HTTP/1.1 408 Request Timeout\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end
end
