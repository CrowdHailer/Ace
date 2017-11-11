defmodule Ace.HTTP.Server do
  @moduledoc false
  use GenServer

  require Logger

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

  @doc """
  Start a new `Ace.HTTP.Server` linked to the calling process.

  A server is started with a reference to a supervisor that can start HTTP workers.

  The server process is returned immediatly.
  This is allow a supervisor to start several servers without waiting for connections.

  To accept a connection `accept_connection/2` must be called.

  A provisioned server will remain in an awaiting state until accept is called.
  """
  def start_link(worker_supervisor, settings \\ []) when is_pid(worker_supervisor) do
    state = %__MODULE__{
      worker_supervisor: worker_supervisor,
      settings: settings,
      socket: nil
    }

    GenServer.start_link(__MODULE__, state)
  end

  @doc """
  Manage a client connect with server

  Accept can only be called once for each server.
  After a connection has been closed the server will terminate.
  """
  def accept_connection(endpoint, listen_socket) do
    GenServer.call(endpoint, {:accept, listen_socket}, :infinity)
  end

  def handle_call({:accept, {:tcp, listen_socket}}, from, state) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        :ok = :inet.setopts(socket, active: :once)
        state = %{state | socket: socket}
        {:ok, worker} = Supervisor.start_child(state.worker_supervisor, [:the_channel])
        monitor = Process.monitor(worker)

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
        # DEBT returns :ok or {:error, :closed}
        :ssl.setopts(socket, active: :once)
        state = %{state | socket: socket}

        case :ssl.negotiated_protocol(socket) do
          {:ok, "h2"} ->
            {:ok, local_settings} = Ace.HTTP2.Settings.for_server(state.settings)

            {:ok, default_server_settings} = Ace.HTTP2.Settings.for_server()

            initial_settings_frame =
              Ace.HTTP2.Settings.update_frame(local_settings, default_server_settings)

            {:ok, default_client_settings} = Ace.HTTP2.Settings.for_client()

            # TODO max table size
            decode_context = Ace.HPack.new_context(4096)
            encode_context = Ace.HPack.new_context(4096)

            {:ok, {_, port}} = :ssl.sockname(listen_socket)

            initial_state = %Ace.HTTP2.Connection{
              socket: socket,
              outbound_window: 65535,
              local_settings: default_server_settings,
              queued_settings: [local_settings],
              remote_settings: default_client_settings,
              # DEBT set when handshaking settings
              decode_context: decode_context,
              encode_context: encode_context,
              streams: %{},
              stream_supervisor: state.worker_supervisor,
              next_local_stream_id: 2,
              name: "SERVER (port: #{port})"
            }

            state = %{initial_state | next: :handshake}
            Logger.debug("#{state.name} sent: #{inspect(initial_settings_frame)}")
            :ok = :ssl.send(state.socket, Ace.HTTP2.Frame.serialize(initial_settings_frame))

            :ssl.setopts(socket, active: :once)

            :gen_server.enter_loop(Ace.HTTP2.Connection, [], {:pending, initial_state})

          response when response in [{:ok, "http/1.1"}, {:error, :protocol_not_negotiated}] ->
            {:ok, worker} = Supervisor.start_child(state.worker_supervisor, [:the_channel])
            monitor = Process.monitor(worker)

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
