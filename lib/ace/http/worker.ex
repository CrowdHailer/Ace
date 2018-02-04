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
  @typep application :: {module, any}

  use GenServer

  @enforce_keys [
    :app_module,
    :app_state,
    :channel,
    :channel_monitor
  ]

  defstruct @enforce_keys

  @doc """
  Start a new worker linked to the calling process.
  """
  @spec start_link(application, :channel) :: GenServer.on_start()
  def start_link({module, config}, channel) do
    GenServer.start_link(__MODULE__, {module, config, channel}, [])
  end

  # NOTE use dynamic supervisor extra_arguments: [app]
  # Works with default GenServer child_spec
  # NOTE Channel needs functions like cleartext? http_version? transport_version
  # NOTE verify_application can be in start_link
  # using Ace.Service should add a `connect(connection, state)` or `init(channel, state)`
  # Can use Ace as a proxy adds header information which is trusted
  # - ace.peer_id
  # - ace.transport: tls

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
  def init({module, config, channel}) do
    channel_monitor = Ace.HTTP.Channel.monitor_endpoint(channel)

    {:ok,
     %__MODULE__{
       app_module: module,
       app_state: config,
       channel: channel,
       channel_monitor: channel_monitor
     }}
  end

  @impl GenServer
  def handle_info({channel, part}, state = %{channel: channel}) do
    handle_raxx_part(part, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state = %{channel_monitor: ref}) do
    {:stop, reason, state}
  end

  def handle_info(other, state) do
    state.app_module.handle_info(other, state.app_state)
    |> normalise_reaction(state.app_state)
    |> do_send(state)
  end

  defp handle_raxx_part(head = %Raxx.Request{}, state) do
    state.app_module.handle_head(head, state.app_state)
    |> normalise_reaction(state.app_state)
    |> do_send(state)
  end

  defp handle_raxx_part(data = %Raxx.Data{}, state) do
    state.app_module.handle_data(data.data, state.app_state)
    |> normalise_reaction(state.app_state)
    |> do_send(state)
  end

  defp handle_raxx_part(tail = %Raxx.Tail{}, state) do
    state.app_module.handle_tail(tail.headers, state.app_state)
    |> normalise_reaction(state.app_state)
    |> do_send(state)
  end

  # TODO this should just be stop state
  defp normalise_reaction(response = %Raxx.Response{}, app_state) do
    {[response], app_state}
  end

  defp normalise_reaction({parts, new_app_state}, app_state) do
    {parts, new_app_state}
  end

  defp do_send({parts, new_app_state}, state) do
    new_state = %{state | app_state: new_app_state}
    {:ok, _channel} = Ace.HTTP.Channel.send(state.channel, parts)

    case List.last(parts) do
      %{body: false} ->
        {:stop, :normal, %{state | app_state: new_app_state}}

      %Raxx.Tail{} ->
        {:stop, :normal, %{state | app_state: new_app_state}}

      %{body: body} when is_binary(body) ->
        {:stop, :normal, %{state | app_state: new_app_state}}

      _ ->
        {:noreply, %{state | app_state: new_app_state}}
    end
  end
end
