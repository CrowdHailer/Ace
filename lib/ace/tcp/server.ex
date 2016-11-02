defmodule Ace.TCP.Server do
  @moduledoc """
  Each `Ace.TCP.Server` manages a single TCP connection.
  They are responsible for managing communication between a TCP client and the larger application.

  The server process accepts as well as manages the connection.
  There is no separate acceptor process.
  This means that that is no need to switch the connections owning process.
  Several erlang servers do use separate acceptor pools.

  ## Example

  The TCP.Server abstracts the common code required to manage a TCP connection.
  Developers only need to their own Server module to define app specific behaviour.

  ```elixir
  defmodule CounterServer do
    def init(_, num) do
      {:nosend, num}
    end

    def handle_packet(_, last) do
      count = last + 1
      {:send, "\#{count}\r\n", count}
    end

    def handle_info(_, last) do
      {:nosend, last}
    end
  end
  ```

  See the README.md for a complete overview on how to make a server available.
  """

  @typedoc """
  Information about the servers connection to the client
  """
  @type connection :: %{peer: {:inet.ip_address, :inet.port_number}}

  @typedoc """
  The current state of an individual server process.
  """
  @type state :: term

  @typedoc """
  The configuration used to start each server.

  A server configuration consists of behaviour, the `module`, and state.
  The module should implement the `Ace.TCP.Server` behaviour.
  Any value can be passed as the state.
  """
  @type app :: {module, state}

  @doc """
  Invoked when a new client connects.
  `accept/2` will block until a client connects and the server has initialised

  The `state` is the second element in the `app` tuple that was used to start the endpoint.

  Returning `{:nosend, state}` will setup a new server with internal `state`.
  The state is perserved in the process loop and passed as the second option to subsequent callbacks.

  Returning `{:nosend, state, timeout}` is the same as `{:send, state}`.
  In addition `handle_info(:timeout, state)` will be called after `timeout` milliseconds, if no messages are received in that interval.

  Returning `{:send, message, state}` or `{:send, message, state, timeout}` is similar to their `:nosend` counterparts,
  except the `message` is sent as the first communication to the client.

  Returning `{:close, state}` will shutdown the server without any messages being sent or recieved
  """
  @callback init(connection, state) ::
    {:send, iodata, state} |
    {:send, iodata, state, timeout} |
    {:nosend, state} |
    {:nosend, state, timeout} |
    {:close, state}

  @doc """
  Every packet recieved from the client invokes this callback.

  The return actions are the same as for the `init/2` callback

  *No additional packets will be taken from the socket until this callback returns*
  """
  @callback handle_packet(binary, state) ::
    {:send, term, state} |
    {:send, term, state, timeout} |
    {:nosend, state} |
    {:nosend, state, timeout} |
    {:close, state}

  @doc """
  Every erlang message recieved by the server invokes this callback.

  The return actions are the same as for the `init/2` callback
  """
  @callback handle_info(term, state) ::
    {:send, term, state} |
    {:send, term, state, timeout} |
    {:nosend, state} |
    {:nosend, state, timeout} |
    {:close, state}

  @doc """
  Called whenever the connection is terminated.
  """
  # All normal sockets should be closed by the client?
  @callback terminate(reason, state) :: term when
    reason: term

  # Use OTP behaviour so the server can be added to a supervision tree.
  use GenServer

  @doc """
  Start a new `Ace.TCP.Server` linked to the calling process.

  A server process is started with an app to describe handling connections.
  The app is a comination of behaviour and state `app = {module, config}`

  The server process is returned immediatly.
  This is allow a supervisor to start several servers without waiting for connections.

  A provisioned server will remain in an awaiting state until accept is called.
  """
  @spec start_link(app) :: GenServer.on_start
  def start_link(app) do
    GenServer.start_link(__MODULE__, {:app, app}, [])
  end

  @doc """
  Take provisioned server to accept the next connection on a socket.

  Accept can only be called once for each server.
  After a connection has been closed the server will terminate.
  """
  @spec accept(server, :inet.socket) :: :ok when
    server: pid
  def accept(server, listen_socket) do
    GenServer.call(server, {:accept, listen_socket}, :infinity)
  end

  ## Server callbacks

  def init({:app, app}) do
    {:ok, {:awaiting, app}}
  end

  def handle_call({:accept, listen_socket}, _from, {:awaiting, {mod, state}}) do
    # Accept and incoming connection request on the listening socket.
    # :timer.sleep(1)
    {:ok, socket} = case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        {:ok, socket}
      {:error, :closed} ->
        exit(:normal)
    end

    # Gather required information from new connection.
    {:ok, peername} = :inet.peername(socket)

    # Initialise the server with the app secification.
    response = mod.init(%{peer: peername}, state)

    # Handle the application response by sending any message and deciding the next step behaviour.
    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:reply, :ok, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:reply, :ok, {{mod, new_state}, socket}, timeout}
      :close ->
        {:stop, :normal, new_state}
    end
  end


  def handle_info({:tcp, socket, packet}, {{mod, state}, socket}) do
    # For any incoming tcp packet call the `handle_packet` action.
    response = mod.handle_packet(packet, state)

    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:noreply, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:noreply, {{mod, new_state}, socket}, timeout}
      :close ->
        {:stop, :normal, new_state}
    end
  end
  def handle_info({:tcp_closed, socket}, {{mod, state}, socket}) do
    # If the socket is closed call the `terminate` action.
    case mod.terminate(:tcp_closed, state) do
      :ok ->
        # FIXME it's normal for sockets to close, might want termination callback to return reason.
        {:stop, :normal, state}
    end
  end
  def handle_info(message, {{mod, state}, socket}) do
    # For any incoming erlang message the `handle_info` action.
    response = mod.handle_info(message, state)

    {new_state, next} = send_response(response, socket)

    case next do
      :normal ->
        {:noreply, {{mod, new_state}, socket}}
      {:timeout, timeout} ->
        {:noreply, {{mod, new_state}, socket}, timeout}
      :close ->
        {:stop, :normal, new_state}
    end
  end

  defp send_response({:send, message, state}, socket) do
    :ok = :gen_tcp.send(socket, message)
    # Set the socket to send a single received packet as a message to this process.
    # This stops the mailbox getting flooded but also also the server to respond to non tcp messages, this was not possible `using gen_tcp.recv`.
    :ok = :inet.setopts(socket, active: :once)
    {state, :normal}
  end
  defp send_response({:send, message, state, timeout}, socket) do
    :ok = :gen_tcp.send(socket, message)
    :ok = :inet.setopts(socket, active: :once)
    {state, {:timeout, timeout}}
  end
  defp send_response({:nosend, state}, socket) do
    :ok = :inet.setopts(socket, active: :once)
    {state, :normal}
  end
  defp send_response({:nosend, state, timeout}, socket) do
    :ok = :inet.setopts(socket, active: :once)
    {state, {:timeout, timeout}}
  end
  defp send_response({:close, state}, socket) do
    :ok = :gen_tcp.close(socket)
    {state, :close}
  end
end
