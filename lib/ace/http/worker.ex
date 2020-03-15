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
  @spec start_link(application, Ace.HTTP.Channel.t()) :: GenServer.on_start()
  def start_link({module, config}, channel) do
    GenServer.start_link(__MODULE__, {module, config, channel}, [])
  end

  @doc false
  def child_spec(channel) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [channel]},
      type: :worker,
      restart: :temporary,
      shutdown: 500
    }
  end

  ## Server Callbacks

  @impl GenServer
  def init({module, config, channel}) do
    channel_monitor = Ace.HTTP.Channel.monitor_endpoint(channel)
    nil = Process.put(Ace.HTTP.Channel, channel)

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
    Ace.HTTP.Channel.ack(channel)

    Raxx.Server.handle({state.app_module, state.app_state}, part)
    |> do_send(state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state = %{channel_monitor: ref}) do
    {:stop, reason, state}
  end

  def handle_info(other, state) do
    Raxx.Server.handle({state.app_module, state.app_state}, other)
    |> do_send(state)
  end

  defp do_send({parts, new_app_state}, state) do
    new_state = %{state | app_state: new_app_state}

    case Ace.HTTP.Channel.send(state.channel, parts) do
      {:ok, _channel} ->
        case List.last(parts) do
          %{body: false} ->
            {:stop, :normal, new_state}

          %Raxx.Tail{} ->
            {:stop, :normal, new_state}

          %{body: body} when is_binary(body) ->
            {:stop, :normal, new_state}

          _ ->
            {:noreply, new_state}
        end

      {:error, :connection_closed} ->
        {:stop, :normal, new_state}
    end
  end
end
