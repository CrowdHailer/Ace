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
  def start(port, app) do
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    # Start a new process that will listen for a connection.
    pid = spawn_link(__MODULE__, :accept, [listen_socket, app])

    # Return the server process
    {:ok, pid}
  end

  def accept(listen_socket, {mod, state}) do

    # Accept and incoming connection request on the listening socket.
    {:ok, socket} = TCP.accept(listen_socket)

    # Initialise the server with the app secification.
    # Enter the message handling loop after sending a message if required.
    case mod.init(:inet.peername(socket), state) do
      {:send, message, new_state} ->
        :ok = TCP.send(socket, message)
        loop(socket, {mod, new_state})
      {:nosend, new_state} ->
        loop(socket, {mod, new_state})
    end

  end

  # Define a loop handler that gets executed for every server action.
  defp loop(socket, app = {mod, state}) do
    # Set the socket to send a single recieved packet as a message to this process.
    # This stops the mailbox getting flooded but also also the server to respond to non tcp messages, this was not possible `using gen_tcp.recv`.
    :ok = :inet.setopts(socket, active: :once)
    receive do
      # For any incoming tcp packet call the `handle_packet` action.
      {:tcp, ^socket, message} ->
        case mod.handle_packet(message, state) do
          {:send, message, new_state} ->
            :ok = TCP.send(socket, message)
            loop(socket, {mod, new_state})
        end
      # If the socket is closed call the `terminate` action.
      # Do not reenter handling loop.
      {:tcp_closed, ^socket} ->
        case mod.terminate(:tcp_closed, state) do
          :ok ->
            :ok
        end
      # For any incoming erlang message the `handle_info` action.
      message ->
        case mod.handle_info(message, state) do
          {:send, message, _state} ->
            :ok = TCP.send(socket, message)
        end
        loop(socket, app)
    end
  end

end
