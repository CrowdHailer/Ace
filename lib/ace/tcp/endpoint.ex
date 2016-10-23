defmodule Ace.TCP.Endpoint do
  @moduledoc """
  Starting the combination of socket, governors and server supervisor.

  Endpoints are started with a fixed pool of governors under the `Ace.TCP.Governor.Supervisor`.
  The number of governors is equal to the maximum number of servers that can be accepting new connections.
  """

  use GenServer

  # Alias erlang libraries so the following code is more readable.

  # Interface for TCP/IP sockets.
  alias :gen_tcp, as: TCP

  # Helpers for the TCP/IP protocols.
  alias :inet, as: Inet

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
  def start_link(app, opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, {app, opts}, [name: name])
  end

  @doc """
  Retrieve the port number for an endpoint.
  """
  def port(endpoint) do
    GenServer.call(endpoint, :port)
  end

  ## Server Callbacks

  def init({app, opts}) do
    port = Keyword.get(opts, :port, 8080)

    # A better name might be acceptors_count, but is rather verbose.
    acceptors = Keyword.get(opts, :acceptors, 50)

    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    {:ok, server_supervisor} = Ace.TCP.Server.Supervisor.start_link(app)
    {:ok, governor_supervisor} = Ace.TCP.Governor.Supervisor.start_link(server_supervisor, listen_socket, acceptors)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    {:ok, {listen_socket, server_supervisor, governor_supervisor}}
  end

  def handle_call(:port, _from, state = {listen_socket, _, _}) do
    port = :inet.port(listen_socket)
    {:reply, port, state}
  end
end
