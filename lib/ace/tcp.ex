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
    # The process must explicity recieve incoming data by calling `TCP.recv/2`
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
  def start(port) do
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    # Start a new process that will listen for a connection.
    pid = spawn_link(__MODULE__, :open, [listen_socket])

    # Return the server process
    {:ok, pid}
  end

  def open(listen_socket) do

    # Accept and incoming connection request on the listening socket.
    {:ok, socket} = TCP.accept(listen_socket)

    # Send a welcome message
    :ok = TCP.send(socket, "WELCOME\r\n")

    # Enter the message handling loop
    loop(socket)
  end

  # Define a loop handler that gets executed on each incoming message.
  defp loop(socket) do
    # Set the socket to send a single recieved package as a message to this process.
    # This stops the mailbox getting flooded but also also the server to respond to non tcp messages, this was not possible `using gen_tcp.recv`.
    :inet.setopts(socket, active: :once)
    receive do
      # For any incoming tcp packet respond by echoing the incomming message.
      {:tcp, ^socket, message} ->
        :ok = TCP.send(socket, "ECHO: #{String.strip(message)}\r\n")
        loop(socket)
      # Send any erlang message that matches this pattern to the connected client.
      {:data, message} ->
        :ok = TCP.send(socket, "#{message}\r\n")
        loop(socket)
      # If the socket is closed print a debug message.
      # Do not reenter handling loop.
      {:tcp_closed, ^socket} ->
        IO.puts("Socket connection closed")
    end
  end
end
