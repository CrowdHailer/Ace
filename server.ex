defmodule TCPEcho do
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

    # FIXME, seams necessary when restarting the server.
    # Problem: the port is not always released when shutting down the server?
    {:reuseaddr, true}
  ]

  def start(port) do
    # Setup a socket to listen with our TCP options
    {:ok, listen_socket} = TCP.listen(port, @tcp_options)

    # Fetch and display the port information for the listening socket.
    {:ok, port} = Inet.port(listen_socket)
    IO.puts("Listening on port: #{port}")

    # Accept and incoming connection request on the listening socket.
    {:ok, socket} = TCP.accept(listen_socket)

    # Enter the message handling loop
    loop(socket)
  end

  # Define a loop handler that gets executed on each incoming message.
  def loop(socket) do
    case TCP.recv(socket, 0) do

      # Close the socket if the incoming message is "CLOSE".
      {:ok, "CLOSE" <> _} ->
        TCP.close(socket)

      # Reply with the message and re-enter loop handler.
      {:ok, message} ->
        TCP.send(socket, "ECHO: #{String.strip(message)}\r\n")
        loop(socket)

      # Shutdown gracefully if the client unexpectedly closed the connection
      {:error, :closed } ->
        IO.puts("Socket connection closed")
    end
  end
end

# Start the echo server on port 8080.
TCPEcho.start(8080)
