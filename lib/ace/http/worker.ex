defmodule Ace.HTTP.Worker do
  use GenServer

  def child_spec({module, config}) do
    # DEBT is module previously checked to implement Raxx.Application or Raxx.Server
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{module, config}]},
      type: :worker,
      restart: :temporary,
      shutdown: 500
    }
  end

  # Onward routing is an interesting challenge.
  # HTTP requests do not have a sensible target.
  # HTTP being stateless is a feature which means you are always calling a new worker
  # A Raxx Server cannont exist unless it is in the context of a channel
  # A HTTP server can start a worker before connection and map its channel reference to streams
  # For 1.0 just start workers as needed.
  def start_link({module, config}, channel) do
    GenServer.start_link(__MODULE__, {module, config, nil}, [])
  end

  ## Server Callbacks

  # conn = stream
  def handle_info({client, request = %Raxx.Request{}}, {mod, state, nil}) do
    mod.handle_headers(request, state)
    |> normalise_reaction({mod, state, client})
  end
  def handle_info({client, fragment = %Raxx.Fragment{}}, {mod, state, client}) do
    mod.handle_fragment(fragment.data, state)
    |> normalise_reaction({mod, state, client})
    |> case do
      {:noreply, {mod, state, client}} ->
        if fragment.end_stream do
          mod.handle_trailers([], state)
          |> normalise_reaction({mod, state, client})
        else
          {:noreply, {mod, state, client}}
        end
    end
  end
  # DEBT I think that the worker should expect to explicitly receive a tail message
  def handle_info({client, trailer = %Raxx.Trailer{}}, {mod, state, client}) do
    mod.handle_trailers(trailer.headers, state)
    |> normalise_reaction({mod, state, client})
  end

  def handle_info(other, {mod, state, client}) do
    mod.handle_info(other, state)
    |> normalise_reaction({mod, state, client})
  end

  defp normalise_reaction(response = %Raxx.Response{}, {mod, state, client}) do
    send_client(client, response)
    if Raxx.complete?(response) do
      {:stop, :normal, {mod, state, client}}
    else
      {:noreply, {mod, state, client}}
    end
  end
  defp normalise_reaction({parts, new_state}, {mod, _old_state, client}) do
    Enum.each(parts, fn(part) -> send_client(client, part) end)
    {:noreply, {mod, new_state, client}}
  end

  defp send_client(ref = {:http1, pid, _count}, part) do
    send(pid, {ref, part})
  end
end
