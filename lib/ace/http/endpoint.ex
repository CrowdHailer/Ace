defmodule Ace.HTTP.Endpoint do
  @moduledoc """

  """
  use GenServer

  defstruct [:worker_supervisor, :settings, :socket]

  # server
  def start_link(worker_supervisor, opts \\ []) when is_pid(worker_supervisor) do
    # Options consist of all connection settings.
    # can think of any required for HTTP1.1
    state = %__MODULE__{
      worker_supervisor: worker_supervisor,
      settings: opts,
      socket: nil
    }
    GenServer.start_link(__MODULE__, state)
  end
  # client
  # def start_link({module, config}, :connection, opts \\ []) do
  #   if connection == :h2 do
  #     GenServer.start_link(Ace.HTTP2.Endpoint, {module, config, nil}, opts)
  #   else
  #   end
  # end

  def accept_connection(endpoint, listen_socket) do
    # Genserver.become Ace.HTTP2.Endpoint
    # OR Genserver.become Ace.HTTP1.Endpoint
    GenServer.call(endpoint, {:accept, listen_socket}, :infinity)
  end

  def handle_call({:accept, listen_socket}, from, state) do
    case accept_connection(listen_socket, from, state) do
      {:ok, socket} ->
        :ok = :ssl.setopts(socket, active: :once)
        state = %{state | socket: socket}
        case :ssl.negotiated_protocol(socket) do
          {:ok, "h2"} ->
            # Change state to HTTP2
            # Possible an install function possible
            # Pull name from socket port
            # Just GET ON with the rewrite that should happen
            # %Ace.HTTP2.Endpoint{
            #
            # }
            # Can become a function later if that is needed
            # Match on preface or frame in handle info
            :gen_server.enter_loop(Ace.HTTP2.Endpoint, [], state)
          {:ok, "http/1.1"} ->
            :gen_server.enter_loop(Ace.HTTP1.Endpoint, [], state)
          {:error, :protocol_not_negotiated} ->
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
    end
    # {:reply, :ok, %{state | socket: socket}}
  end

  defp accept_connection(listen_socket, from, state = %{socket: nil}) do
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

  # Could rename worker channel
  # except channel is to connection as worker is to endpoint
  # Instead of below consider worker process as expendenble and minions to the connection/endpoint process
  def parse() do
    # Take HTTP part and make local
  end

  def serialize do

  end

  def lookup(part) do
    # Find pid that should receive the message
    # This can live in a worker if we consider isolating failures to be reason enough
  end
end
