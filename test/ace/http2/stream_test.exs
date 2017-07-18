defmodule Ace.HTTP2.StreamTest do
  use ExUnit.Case

  @tag :skip
  test "starting a stream as a worker" do
    {:ok, pid} = Supervisor.start_link([], [strategy: :one_for_one])
    Supervisor.start_child(pid, Supervisor.Spec.worker(Stream, [%{}, :config], [restart: :temporary, id: 1]))
    |> IO.inspect
    Supervisor.start_child(pid, Supervisor.Spec.worker(Stream, [%{}, :config], [restart: :temporary, id: 2]))
    |> IO.inspect
    Process.sleep(1_000)
  end
end
