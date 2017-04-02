defmodule Ace.TLS do
  @moduledoc """
  TLS endpoint for secure connections to a service.

  An endpoint is started with a application definition(`Ace.Application`) and configuration.

  Each client connection is handle by an individual server.
  """

  @typedoc """
  Configuration options used when starting and endpoint.
  """
  @type options :: [option]

  @typedoc """
  Option values used to start an endpoint.
  """
  @type option :: {:name, GenServer.name}
                | {:acceptors, non_neg_integer}
                | {:port, :inet.port_number}

  require Logger
  use GenServer

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
    {:reuseaddr, true}
  ]

  @doc """
  Start a secure endpoint with the service.

  ## Options

    * `:certificate` - **required**, the certificate.

    * `:certificate_key` - **required**, the private key used to sign the certificate request.

    * `:port` - the port to run the server on.
      Defaults to port 8443.

    * `:name` - name to register the spawned endpoint under.
      The supported values are the same as GenServers.

    * `:acceptors` - The number of servers simultaneously waiting for a connection.
      Defaults to 50.
  """

  @spec start_link(app, options) :: {:ok, endpoint} when
    app: app,
    endpoint: Ace.TCP.Endpoint.endpoint,
    options: Ace.TCP.Endpoint.options
  def start_link(app = {mod, _}, options) do
    case Ace.Application.is_implemented?(mod) do
      true ->
        :ok
      false ->
        Logger.warn("#{__MODULE__}: #{mod} does not implement Ace.Application behaviour.")
    end
    name = Keyword.get(options, :name)
    GenServer.start_link(__MODULE__, {app, options}, [name: name])
  end

  @doc """
  Retrieve the port number for an endpoint.
  """
  def port(endpoint) do
    GenServer.call(endpoint, :port)
  end

  ## Server Callbacks

  def init({app, options}) do
    port = Keyword.get(options, :port, 8443)
    {:ok, certfile} = Keyword.fetch(options, :certificate)
    {:ok, keyfile} = Keyword.fetch(options, :certificate_key)

    # A better name might be acceptors_count, but is rather verbose.
    acceptors = Keyword.get(options, :acceptors, 50)

    # Setup a socket to listen with our TLS options
    {:ok, listen_socket} = :ssl.listen(port, @socket_options ++ [certfile: certfile, keyfile: keyfile])
    socket = {:tls, listen_socket}

    {:ok, server_supervisor} = Ace.Server.Supervisor.start_link(app)
    {:ok, governor_supervisor} = Ace.Governor.Supervisor.start_link(server_supervisor, socket, acceptors)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Ace.Connection.port(socket)
    name = Keyword.get(options, :name, __MODULE__)
    Logger.debug("#{name} listening on port: #{port}")

    {:ok, {socket, server_supervisor, governor_supervisor}}
  end

  def handle_call(:port, _from, state = {socket, _, _}) do
    port = Ace.Connection.port(socket)
    {:reply, port, state}
  end
end
