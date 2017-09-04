{:ok, _} = Application.ensure_all_started(:httpoison)
ExUnit.start()

defmodule Raxx.Forwarder do
  use Raxx.Server

  def handle_headers(request, state = %{test: pid}) do
    GenServer.call(pid, {:headers, request, state})
  end
  def handle_fragment(data, state = %{test: pid}) do
    GenServer.call(pid, {:fragment, data, state})
  end
  def handle_trailers(trailers, state = %{test: pid}) do
    GenServer.call(pid, {:trailers, trailers, state})
  end
end
