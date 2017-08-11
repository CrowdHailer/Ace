defmodule Ace.HTTP2.Server do
  import Kernel, except: [send: 2]

  def send({:stream, pid, id, ref}, message) do
    Kernel.send(pid, {{:stream, id, ref}, message})
  end

  def push({:stream, pid, id, ref}, request = %{body: false}) do
    Kernel.send(pid, {:push, {:stream, id, ref}, request})
  end
end
