defmodule Ace do
  use Application

  def start(_type, _args) do
    # Ace.Supervisor.start_link
    {:ok, self}
  end
end
defmodule Echo do
  def init(_socket, _env) do
    :nosend
  end

  def handle_packet(packet, _env) do
    {:send, packet}
  end

  def handle_info(_update, _env) do
    :nosend
  end
end

defmodule Greet do
  def init(_socket, message) do
    {:send, message}
  end

  def handle_packet(_packet, _env) do
    :nosend
  end

  def handle_info(_update, _env) do
    :nosend
  end
end

defmodule Broadcast do
  def init(_socket, pid) do
    send(pid, {:register, self()})
    :nosend
  end

  def handle_packet(_packet, _pid) do
    :nosend
  end

  def handle_info(update, _pid) do
    {:send, update}
  end

end
