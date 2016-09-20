defmodule Ace.TCP.Supervisor do
  use Supervisor

  def start_link(options, sup_opts \\ []) do
    Supervisor.start_link(__MODULE__, options, sup_opts)
  end

  # MODULE CALLBACKS

  def init(options) do
    port = options[:port]
    {:ok, listen_socket} = :gen_tcp.listen(port, [{:active, true}, :binary])
    children = [
      worker(Ace.TCP.Session, [listen_socket], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
defmodule Ace.TCP.Session do
  use GenServer

  def start_link(listen_socket, {mod, env}) do
    GenServer.start_link(__MODULE__, {listen_socket, {mod, env}}, [])
  end

  def init(state = {listen_socket, handler}) do
    GenServer.cast(self, :accept)
    {:ok, state}
  end

  def handle_cast(:accept, {listen_socket, {mod, env}}) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)
      case mod.init(socket, env) do
        {:send, greeting} ->
          :gen_tcp.send(socket, greeting)
        :nosend ->
          :ok
      end
      handle(socket, {mod, env})
    {:nosend, {mod, env}}
  end
  defp handle(socket, {mod, env}) do
    receive do
      {:tcp, _socket, packet} ->
        case mod.handle_packet(packet, env) do
          {:send, greeting} ->
            :gen_tcp.send(socket, greeting)
          :nosend ->
            :ok
        end
      info ->
        case mod.handle_info(info, env) do
          {:send, greeting} ->
            :gen_tcp.send(socket, greeting)
          :nosend ->
            :ok
        end
      end
      handle(socket, {mod, env})
    end
end
defmodule Ace.TCP do
  def start_server({mod, env}, opts) do
    port = Enum.into(opts, %{})[:port]
    {:ok, listen_socket} = :gen_tcp.listen(port, [{:active, true}, :binary])
    {:ok, session} = Ace.TCP.Session.start_link(listen_socket, {mod, env})
    {:ok, listen_socket}
  end

  def start_server(mod, opts) do
    start_server({mod, :no_env}, opts)
  end

  def read_port(server) do
    :inet.port(server)
  end

end
