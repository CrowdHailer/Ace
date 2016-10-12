defmodule Ace.TCP do
  @moduledoc """
  TCP connections are handled by the `Ace.TCP` server.

  To start the server run `Ace.TCP.start(port)`.
  """

  # Alias erlang libraries so the following code is more readable.

  # Interface to TCP/IP sockets.
  alias :gen_tcp, as: TCP

  # Helpers for the TCP/IP protocols.
  alias :inet, as: Inet

  # Settings for the TCP socket
  @tcp_options [
    # Received packets are delivered as a binary("string").
    # Alternative option is list('char list').
    {:mode, :binary},

    # Received packets are delineated on each new line.
    {:packet, :line},

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
  Starts the server listening on the given port.
  """
  def start(port, app) do
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    # Start a server process that will listen for a connection.
    {:ok, supervisor} = Ace.TCP.Server.Supervisor.start_link(app)

    # The accept callback is a blocking call.
    # It will only complete once there is a client connection.
    # Therefore it needs to be wrapped in a async task
    # Task.async(Ace.TCP.Server, :accept, [supervisor, listen_socket])
    {:ok, server} = Supervisor.start_child(supervisor, [])
    Task.async(fn
      () ->
        Ace.TCP.Server.accept(server, listen_socket)
    end)

    # Return the server process
    {:ok, supervisor}
  end
end
