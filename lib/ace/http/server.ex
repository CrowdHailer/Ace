defmodule Ace.HTTP.Server do
  @moduledoc false
  use GenServer

  require Logger

  defstruct [:worker_supervisor, :settings, :socket]

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
      settings: settings
    }

    GenServer.start_link(__MODULE__, state)
  end

  @doc false
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
  Manage a client connect with server

  Accept can only be called once for each server.
  After a connection has been closed the server will terminate.
  """
  def accept_connection(endpoint, listen_socket) do
    GenServer.call(endpoint, {:accept, listen_socket}, :infinity)
  end

  def init(args) do
    {:ok, args}
  end

  def handle_call({:accept, listen_socket}, from, state) do
    case Ace.Socket.accept(listen_socket) do
      {:ok, socket} ->
        :ok = Ace.Socket.set_active(socket)

        case Ace.Socket.negotiated_protocol(socket) do
          :http1 ->
            channel = %Ace.HTTP.Channel{
              endpoint: self(),
              id: 1,
              socket: socket
            }

            {:ok, worker} = Supervisor.start_child(state.worker_supervisor, [channel])
            monitor = Process.monitor(worker)

            state = %Ace.HTTP1.Endpoint{
              status: {:request, :response},
              socket: socket,
              # Worker and channel could live on same key, there is no channel without a worker
              channel: channel,
              worker: worker,
              monitor: monitor,
              keep_alive: false,
              receive_state: Ace.HTTP1.Parser.new(max_line_length: 2048),
              pending_ack_count: 0,
              error_response: Keyword.get(state.settings, :error_response)
            }

            GenServer.reply(from, {:ok, self()})
            :gen_server.enter_loop(Ace.HTTP1.Endpoint, [], state)

          :http2 ->
            {:ok, local_settings} = Ace.HTTP2.Settings.for_server(state.settings)

            {:ok, default_server_settings} = Ace.HTTP2.Settings.for_server()

            initial_settings_frame =
              Ace.HTTP2.Settings.update_frame(local_settings, default_server_settings)

            {:ok, default_client_settings} = Ace.HTTP2.Settings.for_client()

            # TODO max table size
            decode_context = Ace.HPack.new_context(4096)
            encode_context = Ace.HPack.new_context(4096)

            {:ok, port} = Ace.Socket.port(listen_socket)

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
            :ok = Ace.Socket.send(state.socket, Ace.HTTP2.Frame.serialize(initial_settings_frame))

            :ok = Ace.Socket.set_active(socket)

            :gen_server.enter_loop(Ace.HTTP2.Connection, [], {:pending, initial_state})
        end

      {:error, reason} ->
        {:stop, :normal, {:error, reason}, state}
    end
  end
end
