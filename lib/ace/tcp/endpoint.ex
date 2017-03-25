defmodule Ace.TCP.Endpoint do
  @moduledoc """
  Starting the combination of socket, governors and server supervisor.

  Endpoints are started with a fixed pool of governors under the `Ace.TCP.Governor.Supervisor`.
  The number of governors is equal to the maximum number of servers that can be accepting new connections.

  An endpoint is configured by the options passed to `start_link/2`.
  """

  require Logger
  use GenServer

  # Settings for the TCP socket
  @tcp_options [
    # Received packets are delivered as a binary("string").
    # Alternative option is list('char list').
    {:mode, :binary},

    # Received packets are delineated on each new line.
    {:packet, :raw},

    # Set the socket to execute in passive mode.
    # The process must explicity receive incoming data by calling `TCP.recv/2`
    {:active, false},

    # it is possible for the process to complete before the kernel has released the associated network resource, and this port cannot be bound to another process until the kernel has decided that it is done.
    # A detailed explaination is given at http://hea-www.harvard.edu/~fine/Tech/addrinuse.html
    # This setting is a security vulnerability only on multi-user machines.
    # It is NOT a vulnerability from outside the machine.
    {:reuseaddr, true}
  ]

  @doc """
  Start a new endpoint with the app behaviour.

  ## Options

    * `:port` - the port to run the server on.
      Defaults to port 8080.

    * `:name` - name to register the spawned endpoint under.
      The supported values are the same as GenServers.

    * `:acceptors` - The number of servers simultaneously waiting for a connection.
      Defaults to 50.

  """
  @typedoc """
  Reference to the endpoint.
  """
  @type endpoint :: pid

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

  @spec start_link(app, options) :: {:ok, endpoint} when
    app: Ace.TCP.Server.app

  def start_link(app, options) do
    name = Keyword.get(options, :name)
    GenServer.start_link(__MODULE__, {app, options}, [name: name])
  end

  @doc """
  Retrieve the port number for an endpoint.
  """
  @spec port(endpoint) :: {:ok, :inet.port_number}
  def port(endpoint) do
    GenServer.call(endpoint, :port)
  end

  ## Server Callbacks

  def init({app, options}) do
    port = Keyword.get(options, :port, 8080)

    # A better name might be acceptors_count, but is rather verbose.
    acceptors = Keyword.get(options, :acceptors, 50)

    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = :gen_tcp.listen(port, @tcp_options)

    {:ok, server_supervisor} = Ace.Server.Supervisor.start_link(app)
    {:ok, governor_supervisor} = Ace.Governor.Supervisor.start_link(server_supervisor, {:tcp, listen_socket}, acceptors)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = :inet.port(listen_socket)
    name = Keyword.get(options, :name, __MODULE__)
    Logger.debug("#{name} listening on port: #{port}")

    {:ok, {listen_socket, server_supervisor, governor_supervisor}}
  end

  def handle_call(:port, _from, state = {listen_socket, _, _}) do
    port = :inet.port(listen_socket)
    {:reply, port, state}
  end
end
