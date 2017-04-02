defmodule CounterServer do
  def handle_connect(_, num) do
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

  def handle_disconnect(_, _) do
    :ok
  end
end

defmodule GreetingServer do
  def init(_, message) do
    {:send, "#{message}\n", []}
  end
  def handle_connect(_, message) do
    {:send, "#{message}\n", []}
  end

  def handle_disconnect(_reason, _state) do
    IO.puts("Socket connection closed")
  end
end

defmodule EchoServer do
  use Ace.Application
  def handle_connect(_, state) do
    {:nosend, state}
  end

  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\n", state}
  end
end

defmodule BroadcastServer do
  def handle_connect(_, pid) do
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

defmodule Timeout do
  def handle_connect(_conn, duration) do
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
  def handle_connect(_conn, test_pid) do
    send(test_pid, {:close, self()})
    {:nosend, test_pid}
  end

  def handle_info(:close, state) do
    {:close, state}
  end
end

ExUnit.start()
