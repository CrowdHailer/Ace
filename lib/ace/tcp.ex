defmodule Ace.TCP do
  @moduledoc """
  Provide a service over TCP.

  To start an enpoint run `Ace.TCP.start/2`.

  Individual TCP connections are handled by the `Ace.TCP.Server` module.
  """

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
  Start a TCP endpoint at the given port.
  """
  def start_endpoint(port, app) do
    # Maybe I should still pass in the socket so that I can access information.
    Supervisor.start_child(Ace.TCP.Endpoint.Supervisor, [app, port: port])
  end

  def start(port, app) do
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    # Start supervisors for the servers and the governors.
    {:ok, server_sup} = Ace.TCP.Server.Supervisor.start_link(app)
    {:ok, _governor_sup} = Ace.TCP.Governor.Supervisor.start_link(server_sup, listen_socket)

    {:ok, listen_socket}
  end
end
