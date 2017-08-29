defmodule Ace.HTTP2.Server do
  @moduledoc """
  Handle interactions with a single HTTP/2 client

  To start an HTTP/2 application use `Ace.HTTP2.Service`

  # Needs docs on stream handlers

  #### Example

  """
  import Kernel, except: [send: 2]

  use GenServer

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

  # TODO move these to HTTP2 or even top level Ace
  def send_response(stream = {:stream, pid, _id, _ref}, response) do
    GenServer.call(pid, {:send_response, stream, response})
  end

  def send_promise(stream = {:stream, pid, _id, _ref}, request = %{body: false}) do
    GenServer.call(pid, {:send_promise, stream, request})
  end

  def send_data(stream = {:stream, pid, _id, _ref}, data, end_stream \\ false) do
    :ok = GenServer.call(pid, {:send_data, stream, %{data: data, end_stream: end_stream}})
  end

  def send_reset(stream = {:stream, pid, _id, _ref}, error) do
    GenServer.call(pid, {:send_reset, stream, error})
  end
end
