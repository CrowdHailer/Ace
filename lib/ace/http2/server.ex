defmodule Ace.HTTP2.Server do
  @moduledoc """
  Handle interactions with a single HTTP/2 client

  To start an HTTP/2 application use `Ace.HTTP2.Service`

  # Needs docs on stream handlers

  #### Example

  """

  # Not a server and a stream worker are not the same thing
  @doc false
  # TODO move back to connection or some other
  def start_link(listen_socket, stream_supervisor, settings \\ nil) do
    settings = if !settings do
      {:ok, default_settings} = Ace.HTTP2.Settings.for_server()
      default_settings
    else
      settings
    end
    GenServer.start_link(Ace.HTTP2.Connection, {listen_socket, stream_supervisor, settings})
  end

  def send_promise(stream = {:stream, pid, _id, _ref}, request = %{body: false}) do
    GenServer.call(pid, {:send_promise, stream, request})
  end
end
