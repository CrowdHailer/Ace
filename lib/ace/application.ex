defmodule Ace.Application do
  @moduledoc false
  # NOTE documentation hidden until HTTP/1.x merged into master.
  # @moduledoc """
  # Behaviour module for implementing a server to handle tcp/tls connections.
  #
  # See `Ace.Server` to start a server with an application
  # ## Example
  #
  # ```elixir
  # defmodule CounterServer do
  #   use Ace.Application
  #
  #   def handle_connect(_, num) do
  #     {:nosend, num}
  #   end
  #
  #   def handle_packet(_, last) do
  #     count = last + 1
  #     {:send, "\#{count}\r\n", count}
  #   end
  #
  #   def handle_info(_, last) do
  #     {:nosend, last}
  #   end
  # end
  # ```
  # """

  @typedoc """
  The current state of a server.
  """
  @type state :: term

  @doc """
  Invoked when a new client connects to the server.

  The `state` is the second element in the `app` tuple that was used to start the endpoint.

  Returning `{:nosend, state}` will setup a new server with internal `state`.
  The state is perserved in the process loop and passed as the second option to subsequent callbacks.

  Returning `{:nosend, state, timeout}` is the same as `{:send, state}`.
  In addition `handle_info(:timeout, state)` will be called after `timeout` milliseconds, if no messages are received in that interval.

  Returning `{:send, message, state}` or `{:send, message, state, timeout}` is similar to their `:nosend` counterparts,
  except the `message` is sent as the first communication to the client.

  Returning `{:close, state}` will shutdown the server without any messages being sent or recieved
  """
  @callback handle_connect(information, state) ::
    {:send, iodata, state} |
    {:send, iodata, state, timeout} |
    {:nosend, state} |
    {:nosend, state, timeout} |
    {:close, state}
  when
    information: Ace.Connection.information()

  @doc """
  Every packet recieved from the client invokes this callback.

  The return actions are the same as for the `handle_disconnect/2` callback

  *No additional packets will be taken from the socket until this callback returns*
  """
  @callback handle_packet(binary, state) ::
    {:send, term, state} |
    {:send, term, state, timeout} |
    {:nosend, state} |
    {:nosend, state, timeout} |
    {:close, state}

  @doc """
  Every message recieved by the server, that was not sent from the client, invokes this callback.

  The return actions are the same as for the `handle_disconnect/2` callback
  """
  @callback handle_info(term, state) ::
    {:send, term, state} |
    {:send, term, state, timeout} |
    {:nosend, state} |
    {:nosend, state, timeout} |
    {:close, state}

  @doc """
  Invoked when connection to the client is lost, or client disconnects.

  *Note a server will not always call `handle_disconnect` on exiting.*
  """
  @callback handle_disconnect(reason, state) :: term when
    reason: term

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end

  @doc """
  Check if a module is an implementation of `Ace.Application`.

      iex> is_implemented?(EchoServer)
      true

      iex> is_implemented?(IO)
      false
  """
  def is_implemented?(module) do
    module.module_info[:attributes]
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(__MODULE__)
  end
end
