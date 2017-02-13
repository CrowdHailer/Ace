defmodule CounterServer do
  def init(_, num) do
    {:nosend, num}
  end

  def handle_packet("TOTAL" <> _rest, count) do
    {:send, "#{count}\r\n", count}
  end
  def handle_packet("INC" <> _rest, last) do
    count = last + 1
    {:nosend, count}
  end

  def handle_info(_, last) do
    {:nosend, last}
  end

  def terminate(_, _) do
    :ok
  end
end

defmodule GreetingServer do
  def init(_, message) do
    {:send, "#{message}\r\n", []}
  end

  def terminate(_reason, _state) do
    IO.puts("Socket connection closed")
  end
end

defmodule EchoServer do
  def init(_, state) do
    {:nosend, state}
  end

  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\r\n", state}
  end
end

defmodule BroadcastServer do
  def init(_, pid) do
    send(pid, {:register, self()})
    {:nosend, pid}
  end

  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\r\n", state}
  end

  def handle_info(_, state) do
    {:nosend, state}
  end
end

defmodule Forwarder do
  @behaviour Ace.TCP.Server

  def init(conn, pid) do
    send(pid, {:conn, conn})
    {:nosend, pid}
  end
end

defmodule Timeout do
  def init(_conn, duration) do
    {:send, "HI\r\n", duration, duration}
  end

  def handle_packet("PING" <> _, duration) do
    {:send, "PONG\r\n", duration, duration}
  end

  def handle_packet(_packet, duration) do
    {:nosend, duration, duration}
  end

  def handle_info(:timeout, duration) do
    {:send, "TIMEOUT #{duration}\r\n", duration}
  end
end

defmodule CloseIt do
  def init(_conn, test_pid) do
    send(test_pid, {:close, self()})
    {:nosend, test_pid}
  end

  def handle_info(:close, state) do
    {:close, state}
  end
end

ExUnit.start()
