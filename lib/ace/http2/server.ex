defmodule Ace.HTTP2.Server do
  @moduledoc """
  Server to handle an the HTTP/2.0 connection of a single client

  # Needs docs on stream handlers

  #### Example

  ```elixir
  defmodule MyApp.StreamHandler do
    use GenServer

    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end

    def handle_info({stream, {:headers, _}}, state) do
      response_headers = %{
        headers: [{":status", "200"}, {"content-length", "13"}],
        end_stream: false
      }
      Server.send(stream, response_headers)
      response_body = %{
        data: "Hello, World!",
        end_stream: true
      }
      Server.send(stream, response_body)
      {:stop, :normal, state}
    end
  end
  ```
  """
  import Kernel, except: [send: 2]

  use GenServer

  def start_link(listen_socket, stream_supervisor, settings \\ nil) do
    settings = if !settings do
      {:ok, default_settings} = Ace.HTTP2.Settings.for_server()
      default_settings
    else
      settings
    end
    GenServer.start_link(Ace.HTTP2.Connection, {listen_socket, stream_supervisor, settings})
  end

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
