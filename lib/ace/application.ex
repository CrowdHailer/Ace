defmodule Ace.Application do
  @moduledoc """
  ## Example

  The `#{__MODULE__}` abstracts the common code required to manage a TCP connection.
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
  """

  @typedoc """
  Information about the servers connection to the client
  """
  @type connection :: %{peer: {:inet.ip_address, :inet.port_number}}

  @typedoc """
  The current state of an individual server process.
  """
  @type state :: term

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
  @callback handle_connect(connection, state) ::
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
  Called whenever the connection to the client is lost.

  *Note a server will not always call `handle_disconnect` on exiting.*
  """
  @callback handle_disconnect(reason, state) :: term when
    reason: term
end
