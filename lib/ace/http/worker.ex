defmodule Ace.HTTP.Worker do
  @moduledoc """
  Run a Raxx application in isolation to handle a single HTTP exchange.

  - The application consists of a behaviour module and initial state.
  - An HTTP exchange is a single response to a single request.

  See `Raxx.Server` for details on implementing a valid module.

  A worker must be started for each message sent.
  Even if messages are sent on a single connection,
  e.g. HTTP pipelining or HTTP/2 streams.
  """
  use GenServer

  @typep application :: {module, any}

  @doc """
  Start a new worker linked to the calling process.
  """
  @spec start_link(application) :: GenServer.on_start()
  def start_link({module, config}) do
    GenServer.start_link(__MODULE__, {module, config, nil}, [])
  end

  @doc false
  def child_spec(app) do
    # NOTE child spec is called only once so possibly expensive call to `Code.ensure_compiled?` is not repeated
    # `start_link` in this module could be protected by dialyzer
    case Raxx.verify_application(app) do
      {:ok, app} ->
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [app]},
          type: :worker,
          restart: :temporary,
          shutdown: 500
        }

      {:error, message} ->
        raise message
    end
  end

  ## Server Callbacks

  @impl GenServer
  def handle_info({client, request = %Raxx.Request{}}, {mod, state, nil}) do
    case client do
      {:http1, endpoint, _id} ->
        Process.monitor(endpoint)

      {:stream, endpoint, _id, _ref} ->
        Process.monitor(endpoint)
    end

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

  def handle_info({:DOWN, _r, :process, p, reason}, {mod, state, client = {:http1, p, _id}}) do
    {:stop, reason, {mod, state, client}}
  end

  def handle_info(
        {:DOWN, _r, :process, p, reason},
        {mod, state, client = {:stream, p, _id, _ref}}
      ) do
    {:stop, reason, {mod, state, client}}
  end

  def handle_info(other, {mod, state, client}) do
    mod.handle_info(other, state)
    |> normalise_reaction(state)
    |> do_send({mod, state, client})
  end

  defp normalise_reaction(response = %Raxx.Response{}, state) do
    {[response], state}
  end

  defp normalise_reaction({parts, new_state}, _old_state) do
    parts = Enum.map(parts, &fix_part/1)
    {parts, new_state}
  end

  defp do_send({parts, new_state}, {mod, _old_state, client}) do
    case parts do
      [] ->
        {:noreply, {mod, new_state, client}}

      parts ->
        case client do
          ref = {:http1, pid, _count} ->
            send(pid, {ref, parts})

          stream = {:stream, _, _, _} ->
            Enum.each(parts, fn part ->
              Ace.HTTP2.send(stream, part)
            end)
        end

        case List.last(parts) do
          %{body: false} ->
            {:stop, :normal, {mod, new_state, client}}

          %Raxx.Tail{} ->
            {:stop, :normal, {mod, new_state, client}}

          %{body: body} when is_binary(body) ->
            {:stop, :normal, {mod, new_state, client}}

          _ ->
            {:noreply, {mod, new_state, client}}
        end
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
