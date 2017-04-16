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
end
