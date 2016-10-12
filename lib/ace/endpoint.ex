defmodule Ace.TCP.Endpoint do
  use Supervisor

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

  def start_link(app, opts \\ [], sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, {app, opts}, sup_opts)
  end

  ## Supervisor Callbacks

  def init({app, opts}) do
    port = Keyword.get(opts, :port, 8080)
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    # Instead of providing the name for the server supervisor, this supervisor could commit suicide and then it would be restarted by the endpoint supervisor.
    children = [
      supervisor(Ace.TCP.Server.Supervisor, [app, [name: :"Server.Supervisor.#{port}"]]),
      supervisor(Ace.TCP.Governor.Supervisor, [:"Server.Supervisor.#{port}", listen_socket])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
