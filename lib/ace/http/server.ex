defmodule Ace.HTTP.Server do
  @moduledoc false
  use GenServer

  defstruct [:worker_supervisor, :settings, :socket]

  def child_spec({worker_supervisor, settings}) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [worker_supervisor, settings]},
      type: :worker,
      restart: :temporary,
      shutdown: 500
    }
  end

  def start_link(worker_supervisor, settings \\ []) when is_pid(worker_supervisor) do
    state = %__MODULE__{
      worker_supervisor: worker_supervisor,
      settings: settings,
      socket: nil
    }
    GenServer.start_link(__MODULE__, state)
  end

  def accept_connection(endpoint, listen_socket) do
    GenServer.call(endpoint, {:accept, listen_socket}, :infinity)
  end

  def handle_call({:accept, {:tcp, listen_socket}}, from, state) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        :ok = :inet.setopts(socket, active: :once)
        state = %{state | socket: socket}
        {:ok, worker} = Supervisor.start_child(state.worker_supervisor, [:the_channel])
        state = %Ace.HTTP1.Endpoint{
          status: {:request, :response},
          socket: {:tcp, socket},
          # Worker and channel could live on same key, there is no channel without a worker
          channel: {:http1, self(), 1},
          worker: worker
        }
        GenServer.reply(from, {:ok, self()})
        :gen_server.enter_loop(Ace.HTTP1.Endpoint, [], {"", state})
      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end
  def handle_call({:accept, listen_socket}, from, state) do
    case ssl_accept_connection(listen_socket, from, state) do
      {:ok, socket} ->
        :ok = :ssl.setopts(socket, active: :once)
        state = %{state | socket: socket}
        case :ssl.negotiated_protocol(socket) do
          # TODO atm only http/1.1 is an accepted protocol
          {:ok, "h2"} ->
            :gen_server.enter_loop(Ace.HTTP2.Endpoint, [], state)
          response when response in [{:ok, "http/1.1"}, {:error, :protocol_not_negotiated}] ->
            {:ok, worker} = Supervisor.start_child(state.worker_supervisor, [:the_channel])
            state = %Ace.HTTP1.Endpoint{
              status: {:request, :response},
              socket: socket,
              # Worker and channel could live on same key, there is no channel without a worker
              channel: {:http1, self(), 1},
              worker: worker
            }
            GenServer.reply(from, {:ok, self()})
            :gen_server.enter_loop(Ace.HTTP1.Endpoint, [], {"", state})
        end
      {:error, :closed} ->
        {:reply, {:error, :closed}, state}
    end
  end

  defp ssl_accept_connection(listen_socket, from, state = %{socket: nil}) do
    case :ssl.transport_accept(listen_socket) do
      {:ok, socket} ->
        case :ssl.ssl_accept(socket) do
          :ok ->
            {:ok, socket}
          {:error, :closed} ->
            {:error, :econnaborted}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
end
