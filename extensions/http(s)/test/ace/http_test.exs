defmodule Ace.HTTPTest do
  use ExUnit.Case, async: true
  doctest Ace.HTTP

  setup config do
    {:ok, endpoint} = Ace.HTTP.start_link({__MODULE__, config |> Map.put(:pid, self())}, port: 0)
    {:ok, port} = Ace.HTTP.port(endpoint)
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

  def handle_error({:invalid_request_line, data}) do
    Raxx.Response.bad_request([{"connection", "close"}, {"content-length", "0"}])
  end

  test "400 response for invalid start_line", %{port: port} do
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, "rubbish\n")
    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  def handle_error({:invalid_header_line, line}) do
    Raxx.Response.bad_request([{"connection", "close"}, {"content-length", "0"}])
  end

  test "400 response for invalid headers", %{port: port} do
    {:ok, connection} = :gen_tcp.connect({127,0,0,1}, port, [:binary])
    :gen_tcp.send(connection, "GET / HTTP/1.1\r\na \r\n::\r\n")
    assert_receive {:tcp, ^connection, response}, 1_000
    assert response == "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end
end
