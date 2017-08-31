defmodule Ace.HTTP2.Server do
  @moduledoc false

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
end
