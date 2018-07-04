defmodule Ace.HTTP.Service do
  @moduledoc """
  Run a `Raxx.Server` application for HTTP/1.x and HTTP/2 clients

  **NOTE:** Ace services are served over a secure transport layer TLS(SSL),
  therefore `:cert` + `:key` or `:certfile` + `:keyfile` are required options.

  Starting a service will start and manage a cohort of endpoint process.
  The number of awaiting endpoint processes is set by the `:acceptors` option.

  Each endpoint process manages communicate to a single connected client.
  Using HTTP/1.1 pipelining of HTTP/2 multiplexing one connection may be used for multiple HTTP exchanges.
  An HTTP exchange consisting of one request from the client and one response from the server.

  Each exchange is isolated in a dedicated worker process.
  Raxx specifies early abortion of an exchange can be achieved by causing the worker process to exit.
  """

  use GenServer

  require Logger

  @socket_options [
    # Received packets are delivered as a binary("string").
    {:mode, :binary},

    # Handle packets as soon as they are available.
    {:packet, :raw},

    # Set the socket to execute in passive mode, it must be prompted to read data.
    {:active, false},

    # it is possible for the process to complete before the kernel has released the associated network resource, and this port cannot be bound to another process until the kernel has decided that it is done.
    # A detailed explaination is given at http://hea-www.harvard.edu/~fine/Tech/addrinuse.html
    # This setting is a security vulnerability only on multi-user machines.
    # It is NOT a vulnerability from outside the machine.
    {:reuseaddr, true},
    {:alpn_preferred_protocols, ["h2", "http/1.1"]}
  ]

  @typedoc """
  Process to manage a HTTP service.

  This process should be added to a supervision tree as a supervisor.
  """
  @type service :: pid

  defmacro __using__(defaults) do
    {defaults, []} = Module.eval_quoted(__CALLER__, defaults)

    quote do
      use Raxx.Server

      def start_link(initial_state, options \\ []) do
        application = {__MODULE__, initial_state}
        options = options ++ unquote(defaults)
        unquote(__MODULE__).start_link(application, options)
      end

      def child_spec([]) do
        child_spec([%{}])
      end

      def child_spec([config]) do
        child_spec([config, []])
      end

      def child_spec([config, options]) do
        %{
          id: Keyword.get(options, :id, __MODULE__),
          start: {__MODULE__, :start_link, [config, options]},
          type: :supervisor,
          restart: :permanent
        }
      end
    end
  end

  @doc """
  Start a HTTP web service.

  ## Options

    * `:cleartext` - Serve over TCP rather than TLS(ssl), will not support HTTP/2.

    * `:certfile` - the certificate.

    * `:keyfile` - the private key used to sign the certificate request.

    * `:cert` - the certificate.

    * `:key` - the private key used to sign the certificate request.

    * `:port` - the port to run the server on.
      Defaults to port 8443.

    * `:name` - name to register the spawned endpoint under.
      The supported values are the same as GenServers.

    * `:acceptors` - The number of servers simultaneously waiting for a connection.
      Defaults to 100.
  """
  @spec start_link({module, any}, [{atom, any}]) :: {:ok, service}
  def start_link(app = {_module, _config}, options) do
    case Ace.HTTP2.Settings.for_server(options) do
      {:ok, _settings} ->
        service_options = Keyword.take(options, [:name])
        GenServer.start_link(__MODULE__, {app, options}, service_options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def child_spec([{mod, config}, options]) do
    %{
      id: Keyword.get(options, :id, __MODULE__),
      start: {__MODULE__, :start_link, [{mod, config}, options]},
      type: :supervisor,
      restart: :permanent
    }
  end

  @doc """
  Fetch the port number of a running service.

  **OS assigned ports:**
  If an endpoint is started with port number `0` it will be assigned a port by the underlying system.
  This can be used to start many endpoints simultaneously.
  It can be useful running parallel tests.
  """
  @spec port(service) :: {:ok, :inet.port_number()}
  def port(service) do
    GenServer.call(service, :port)
  end

  @doc """
  Returns a number of connected clients for a given service.
  """
  @spec count_connections(service) :: non_neg_integer()
  def count_connections(service) do
    GenServer.call(service, :count_connections)
  end

  ## SERVER CALLBACKS

  @impl GenServer
  def init({app, options}) do
    port =
      case Keyword.fetch(options, :port) do
        {:ok, port} when is_integer(port) ->
          port

        _ ->
          raise "#{__MODULE__} must be started with a port to listen too."
      end

    acceptors = Keyword.get(options, :acceptors, 100)

    listen_socket =
      case Keyword.fetch(options, :cleartext) do
        {:ok, true} ->
          tcp_options =
            Keyword.take(@socket_options ++ options, [:mode, :packet, :active, :reuseaddr])

          {:ok, listen_socket} = :gen_tcp.listen(port, tcp_options)
          listen_socket = {:tcp, listen_socket}
          {:ok, port} = Ace.Socket.port(listen_socket)
          Logger.info("Serving cleartext using HTTP/1 on port #{port}")
          listen_socket

        _ ->
          ssl_options =
            Keyword.take(@socket_options ++ options, [
              :mode,
              :packet,
              :active,
              :reuseaddr,
              :alpn_preferred_protocols,
              :cert,
              :key,
              :certfile,
              :keyfile
            ])

          {:ok, listen_socket} = :ssl.listen(port, ssl_options)
          listen_socket = {:ssl, listen_socket}
          {:ok, port} = Ace.Socket.port(listen_socket)
          Logger.info("Serving securely using HTTP/1 and HTTP/2 on port #{port}")
          listen_socket
      end

    {:ok, worker_supervisor} =
      Supervisor.start_link(
        [{Ace.HTTP.Worker, app}],
        strategy: :simple_one_for_one,
        max_restarts: 5000
      )

    {:ok, endpoint_supervisor} =
      Supervisor.start_link(
        [{Ace.HTTP.Server, {worker_supervisor, options}}],
        strategy: :simple_one_for_one,
        max_restarts: 5000
      )

    # DEBT reduce restarts
    {:ok, governor_supervisor} =
      Supervisor.start_link(
        [{Ace.Governor, {endpoint_supervisor, listen_socket}}],
        strategy: :simple_one_for_one,
        max_restarts: 5000
      )

    for _index <- 1..acceptors do
      Supervisor.start_child(governor_supervisor, [])
    end

    {:ok, {listen_socket, worker_supervisor, endpoint_supervisor, governor_supervisor}}
  end

  @impl GenServer
  def handle_call(:port, _from, state = {listen_socket, _, _, _}) do
    {:reply, Ace.Socket.port(listen_socket), state}
  end

  def handle_call(:count_connections, _from, state) do
    {_listen_socket, worker_supervisor, _endpoint_supervisor, _governor_supervisor} = state
    count = Supervisor.count_children(worker_supervisor).active
    {:reply, count, state}
  end
end
