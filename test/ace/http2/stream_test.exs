defmodule Ace.HTTP2.StreamTest do
  use ExUnit.Case

  defmodule Stream do
    use GenServer

    # Probably needs a consumer for sending data
    def start_link(headers, config) do
      GenServer.start_link(__MODULE__, {headers, config})
    end

    def init({headers, config}) do
      IO.inspect(headers)
      send(self(), {__MODULE__, :open, headers})
      {:ok, %{config: config}}
    end

    def handle_info({__MODULE__, :open, headers}, state = %{config: config}) do
      handle_open(headers, :response, config)
      {:noreply, state}
    end

    def handle_open(headers, response, config) do
      :ok
    end
  end


  test "starting a stream as a worker" do
    {:ok, pid} = Supervisor.start_link([], [strategy: :one_for_one])
    Supervisor.start_child(pid, Supervisor.Spec.worker(Stream, [%{}, :config], [restart: :temporary, id: 1]))
    |> IO.inspect
    Supervisor.start_child(pid, Supervisor.Spec.worker(Stream, [%{}, :config], [restart: :temporary, id: 2]))
    |> IO.inspect
    Process.sleep(1_000)
  end
end
