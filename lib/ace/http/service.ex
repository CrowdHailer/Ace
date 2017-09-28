defmodule Ace.HTTP.Service do
  @moduledoc """
  Run a `Raxx.Server` application for HTTP/1.x and HTTP/2 clients

  **NOTE:** Ace services are served over a secure transport layer TLS(SSL),
  therefore `:cert` + `:key` or `:certfile` + `:keyfile` are required options.

  Starting a service will start and manage a cohort of endpoint process.
  The number of awaiting endpoint processes is set by the acceptors option.

  Each endpoint process manages communicate to a single connected client.
  Using HTTP/1.1 pipelining of HTTP/2 multiplexing one connection may be used for multiple HTTP exchanges.
  An HTTP exchange consisting of one request from the client and one response from the server.

  Each exchange is isolated in a dedicated worker process.
  Raxx specifies early abortion of an exchange can be achieved by causing the worker process to exit.
  """

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

    # TODO change for HTTP/2 support
    {:alpn_preferred_protocols, ["http/1.1"]}
    # {:alpn_preferred_protocols, ["h2", "http/1.1"]}
  ]

  @doc """
  Start a HTTP web application.
  """
  def start_link(app = {module, config}, options) do
    # TODO test that module implements `Raxx.Server`
    service_options = Keyword.take(options, [:name])
    GenServer.start_link(__MODULE__, {app, options}, service_options)
  end

  @doc """
  Fetch the port number of a running service.

  **OS assigned ports:**
  If an endpoint is started with port number `0` it will be assigned a port by the underlying system.
  This can be used to start many endpoints simultaneously.
  It can be useful running parallel tests.
  """
  def port(endpoint) do
    GenServer.call(endpoint, :port)
  end

  ## SERVER CALLBACKS

  defmodule Governor do
    @moduledoc false

    def child_spec({endpoint_supervisor, listen_socket}) do
      # DEBT is module previously checked to implement Raxx.Application or Raxx.Server
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [endpoint_supervisor, listen_socket]},
        type: :worker,
        restart: :transient,
        shutdown: 500
      }
    end

    def start_link(endpoint_supervisor, listen_socket) do
      GenServer.start_link(__MODULE__, {listen_socket, endpoint_supervisor})
    end

    def init(state = {listen_socket, endpoint_supervisor}) do
      send(self(), :start)
      {:ok, state}
    end

    def handle_info(:start, state = {listen_socket, endpoint_supervisor}) do
      {:ok, server} = Supervisor.start_child(endpoint_supervisor, [])
      Ace.HTTP.Server.accept_connection(server, listen_socket)
      handle_info(:start, state)
    end
  end

  @doc false
  def init({app, options}) do
    port = case Keyword.fetch(options, :port) do
      {:ok, port} when is_integer(port) ->
        port
      _ ->
        raise "#{__MODULE__} must be started with a port to listen too."
    end

    acceptors = Keyword.get(options, :acceptors, 100)

    listen_socket = case Keyword.fetch(options, :cleartext) do
      {:ok, true} ->
        tcp_options = Keyword.take(@socket_options ++ options, [:mode, :packet, :active, :reuseaddr])
        {:ok, listen_socket} = :gen_tcp.listen(port, tcp_options)
        Logger.info("Serving cleartext using HTTP/1")
        {:tcp, listen_socket}
      _ ->
        {:ok, listen_socket} = :ssl.listen(port, @socket_options ++ options)
        Logger.info("Serving securly using HTTP/1, for HTTP/2 use Ace.HTTP2.Service directly")
        listen_socket
    end

    {:ok, worker_supervisor} = Supervisor.start_link(
      [{Ace.HTTP.Worker, app}],
      [strategy: :simple_one_for_one]
    )
    {:ok, endpoint_supervisor} = Supervisor.start_link(
      [{Ace.HTTP.Server, {worker_supervisor, options}}],
      [strategy: :simple_one_for_one]
    )
    {:ok, governor_supervisor} = Supervisor.start_link(
      # TODO move this to a proper module
      [{Governor, {endpoint_supervisor, listen_socket}}],
      [strategy: :simple_one_for_one]
    )

    for _index <- 1..acceptors do
      Supervisor.start_child(governor_supervisor, [])
    end

    {:ok, {listen_socket, worker_supervisor, endpoint_supervisor, governor_supervisor}}
  end

  @doc false
  def handle_call(:port, _from, state = {{:tcp, listen_socket}, _, _, _}) do
    {:reply, :inet.port(listen_socket), state}
  end
  def handle_call(:port, _from, state = {listen_socket, _, _, _}) do
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {:reply, {:ok, port}, state}
  end
end
