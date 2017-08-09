defmodule Ace.HTTP2.Server do
  import Kernel, except: [send: 2]

  def send({:stream, pid, id, ref}, message) do
    Kernel.send(pid, {{:stream, id, ref}, message})
  end
end
