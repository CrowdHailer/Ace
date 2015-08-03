alias :gen_tcp, as: TCP
alias :inet, as: Inet

tcp_options = [
  :binary,
  {:packet, :line},
  {:reuseaddr, true},
  {:active, false},
  # {:backlog, backlog}
]
{:ok, listen_socket} = TCP.listen(0, tcp_options)

{:ok, port} = Inet.port(listen_socket)
IO.puts "Listening on port: #{port}"

{:ok, socket} = TCP.accept(listen_socket)


defmodule TCPEcho do
  def handle({:ok, "CLOSE" <> _}) do
    {:close}
  end

  def handle({:ok, message}) do
    message
      |> String.strip
      |> IO.inspect
    {:ok}
  end

  def loop(socket) do
    case handle TCP.recv(socket, 0) do
      {:ok} -> loop(socket)
      {:close} -> TCP.close(socket)
    end
  end

end

TCPEcho.loop(socket)
