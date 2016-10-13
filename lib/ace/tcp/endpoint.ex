defmodule Ace.TCP.Endpoint do

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

  def start_link(app, opts, gen_opts \\ []) do
    port = Keyword.get(opts, :port, 8080)
    GenServer.start_link(__MODULE__, {app, opts}, [name: :"Endpoint{#{port}}"])
  end

  def init({app, opts}) do
    port = Keyword.get(opts, :port, 8080)
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    {:ok, server_supervisor} = Ace.TCP.Server.Supervisor.start_link(app)
    {:ok, governor_supervisor} = Ace.TCP.Governor.Supervisor.start_link(server_supervisor, listen_socket)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    {:ok, {listen_socket, server_supervisor, governor_supervisor}}
  end

  def handle_info(m, s) do
    IO.inspect(m)
    {:noreply, s}
  end

  def terminate(r, s) do
    IO.inspect(r)
    {:ok, r}
  end
end
