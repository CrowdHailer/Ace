defmodule Ace.HTTP.Worker do
  @moduledoc false
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

  # TODO decide whether a channel should be limited from startup to single channel (stream/pipeline)
  def start_link({module, config}, channel \\ nil) do
    GenServer.start_link(__MODULE__, {module, config, nil}, [])
  end

  ## Server Callbacks

  def handle_info({client, request = %Raxx.Request{}}, {mod, state, nil}) do
    mod.handle_head(request, state)
    |> normalise_reaction(state)
    |> do_send({mod, state, client})
  end

  def handle_info({client, data = %Raxx.Data{}}, {mod, state, client}) do
    mod.handle_data(data.data, state)
    |> normalise_reaction(state)
    |> do_send({mod, state, client})
  end

  def handle_info({client, tail = %Raxx.Tail{}}, {mod, state, client}) do
    mod.handle_tail(tail.headers, state)
    |> normalise_reaction(state)
    |> do_send({mod, state, client})
  end

  def handle_info(other, {mod, state, client}) do
    mod.handle_info(other, state)
    |> normalise_reaction(state)
    |> do_send({mod, state, client})
  end

  defp normalise_reaction(response = %Raxx.Response{}, state) do
    case response.body do
      false ->
        {[response], state}

      true ->
        {[response], state}

      _body ->
        # {[%{response | body: true}, Raxx.data(response.body), Raxx.tail], state}
        {[response], state}
    end
  end

  defp normalise_reaction({parts, new_state}, _old_state) do
    parts = Enum.map(parts, &fix_part/1)
    {parts, new_state}
  end

  defp do_send({parts, new_state}, {mod, _old_state, client}) do
    case parts do
      [] ->
        :ok

      parts ->
        case client do
          ref = {:http1, pid, _count} ->
            send(pid, {ref, parts})

          stream = {:stream, _, _, _} ->
            Enum.each(parts, fn part ->
              Ace.HTTP2.send(stream, part)
            end)
        end
    end

    case List.last(parts) do
      %{body: false} ->
        {:stop, :normal, {mod, new_state, client}}

      %Raxx.Tail{} ->
        {:stop, :normal, {mod, new_state, client}}
        
      %{body: x} when is_binary(x) ->
        {:stop, :normal, {mod, new_state, client}}

      _ ->
        {:noreply, {mod, new_state, client}}
    end
  end

  # TODO remove this special case
  defp fix_part({:promise, request}) do
    request =
      request
      |> Map.put(:scheme, request.scheme || :https)

    {:promise, request}
  end

  defp fix_part(part) do
    part
  end
end
