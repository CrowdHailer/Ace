defmodule Ace.HTTP.ResponseTest do
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

  test "server can send a complete response after receiving headers", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, _state}}, 1_000
    response = Raxx.response(:ok)
    |> Raxx.set_header("content-length", "2")
    |> Raxx.set_header("x-test", "Value")
    |> Raxx.set_body("OK")
    GenServer.reply(from, response)

    assert_receive {:tcp, ^socket, response}, 1_000

    assert response == "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 2\r\nx-test: Value\r\n\r\nOK"
  end

  test "server can stream response with a predetermined size", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, state}}, 1_000
    response = Raxx.response(:ok)
    |> Raxx.set_header("content-length", "15")
    |> Raxx.set_header("x-test", "Value")
    |> Raxx.set_body(true)
    GenServer.reply(from, {[response], state})

    assert_receive {:tcp, ^socket, response_head}, 1_000

    assert response_head == "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 15\r\nx-test: Value\r\n\r\n"

    {server, _ref} = from
    send(server, {[Raxx.fragment("Hello, ")], state})

    assert_receive {:tcp, ^socket, "Hello, "}, 1_000
    send(server, {[Raxx.fragment("World!\r\n", true)], state})

    assert_receive {:tcp, ^socket, "World!\r\n"}, 1_000
  end

  test "content-length will be added for a complete response", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, _state}}, 1_000
    response = Raxx.response(:ok)
    |> Raxx.set_header("x-test", "Value")
    |> Raxx.set_body("OK")
    GenServer.reply(from, response)

    assert_receive {:tcp, ^socket, response}, 1_000

    assert response == "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 2\r\nx-test: Value\r\n\r\nOK"
  end

  test "content-length will be added for a response with no body", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, _state}}, 1_000
    response = Raxx.response(:ok)
    |> Raxx.set_header("x-test", "Value")
    |> Raxx.set_body(false)
    GenServer.reply(from, response)

    assert_receive {:tcp, ^socket, response}, 1_000

    assert response == "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 0\r\nx-test: Value\r\n\r\n"
  end
end
