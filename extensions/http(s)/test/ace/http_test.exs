defmodule Ace.HTTPTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog, only: [capture_log: 1]
  
  doctest Ace.HTTP

  setup config do
    raxx_app = {__MODULE__, config |> Map.put(:pid, self())}
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

  def handle_request(%{path: ["chunked"]}, %{pid: pid}) do
    send(pid, {:server, self()})
    %Ace.ChunkedResponse{
      status: 200,
      headers: [{"transfer-encoding", "chunked"}, {"cache-control", "no-cache"}]
    }
  end

  def handle_info(chunks, _) do
    chunks
  end

  test "chunked responses from same app", %{port: port} do
    HTTPoison.get("localhost:#{port}/chunked", %{}, stream_to: self())
    server = receive do
      {:server, server} -> server
    end
    send(server, ["content"])
    send(server, [""])
    assert_receive %{code: 200}, 1000
    assert_receive %{headers: [_, _]}, 1000
    assert_receive %{chunk: "content"}, 1000
  end

  def handle_request(%{path: ["upgrade"]}, %{pid: pid}) do
    send(pid, {:server, self()})
    %Ace.ChunkedResponse{
      status: 200,
      headers: [{"transfer-encoding", "chunked"}, {"cache-control", "no-cache"}],
      app: {__MODULE__.Streaming, :new}
    }
  end

  defmodule Streaming do
    def handle_info(chunks, :new) do
      chunks
    end
  end

  test "chunked responses from upgraded server", %{port: port} do
    HTTPoison.get("localhost:#{port}/upgrade", %{}, stream_to: self())
    server = receive do
      {:server, server} -> server
    end
    send(server, ["content"])
    send(server, [""])
    assert_receive %{chunk: "content"}, 1000
  end

  def handle_error({:invalid_request_line, _data}) do
    Raxx.Response.bad_request([{"connection", "close"}, {"content-length", "0"}])
  end

  test "400 response for invalid start_line", %{port: port} do
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, "rubbish\n")
    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  def handle_error({:invalid_header_line, _line}) do
    Raxx.Response.bad_request([{"connection", "close"}, {"content-length", "0"}])
  end

  test "400 response for invalid headers", %{port: port} do
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, "GET / HTTP/1.1\r\na \r\n::\r\n")
    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  def handle_error(:start_line_too_long) do
    Raxx.Response.uri_too_long([{"connection", "close"}, {"content-length", "0"}])
  end

  test "test too long url ", %{port: port} do
    path = for _i <- 1..3000 do
      "a"
    end |> Enum.join("")
    # |> IO.inspect
    request = """
    GET /#{path} HTTP/1.1
    Host: www.raxx.com

    """
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, request)
    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 414 URI Too Long\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  def handle_error(:body_timeout) do
    Raxx.Response.request_timeout([{"connection", "close"}, {"content-length", "0"}])
  end

  test "Client too slow to deliver body", %{port: port} do
    head = """
    GET / HTTP/1.1
    Host: www.raxx.com
    Content-Length: 100

    """
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, head)
    assert_receive {:tcp, ^connection, response}, 15_000
    assert response == "HTTP/1.1 408 Request Timeout\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  def handle_error({:body_too_large, _}) do
    Raxx.Response.payload_too_large([{"connection", "close"}, {"content-length", "0"}])
  end

  test "Request is too large", %{port: port} do
    head = """
    GET / HTTP/1.1
    Host: www.raxx.com
    Content-Length: 100000000

    """
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, head)
    assert_receive {:tcp, ^connection, response}, 15_000
    assert response == "HTTP/1.1 413 Payload Too Large\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  # TODO test slow client attack
end
