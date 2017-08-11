defmodule Ace.HTTP2.Server do
  import Kernel, except: [send: 2]

  use GenServer

  def start_link(listen_socket, stream_supervisor) do
    GenServer.start_link(Ace.HTTP2.Connection, {listen_socket, stream_supervisor})
  end

  def send_response(stream = {:stream, pid, _id, _ref}, response) do
    GenServer.call(pid, {:send_response, stream, response})
  end

  def send_promise(stream = {:stream, pid, _id, _ref}, request = %{body: false}) do
    GenServer.call(pid, {:send_promise, stream, request})
  end

  def send_reset(stream = {:stream, pid, _id, _ref}, error, debug \\ "") do
    GenServer.call(pid, {:send_reset, stream, error, debug})
  end
end
