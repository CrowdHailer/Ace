defmodule Ace.Socket do
  @moduledoc """
  Wrapper to normalise interactions with tcp or tls sockets.

  NOTE: tls sockets use the `:ssl` module and are identified with `:ssl` atom
  """
  @moduledoc false

  @typedoc """
  Wrapped tcp socket or tls socket.
  """
  @type t :: {:tcp, :inet.socket()} | {:ssl, :"ssl.SslSocket"}
  @typedoc """
  Wrapped listen socket.
  """
  @type listen_socket :: {:ssl, :"ssl.ListenSocket"} | {:tcp, :inet.socket()}

  require OK

  def accept({:tcp, listen_socket}) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        {:ok, {:tcp, socket}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def accept({:ssl, listen_socket}) do
    case :ssl.transport_accept(listen_socket) do
      {:ok, socket} ->
        case :ssl.ssl_accept(socket) do
          :ok ->
            {:ok, {:ssl, socket}}

          {:error, :closed} ->
            {:error, :econnaborted}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def connect(endpoint = "http://" <> _) do
    uri = URI.parse(endpoint)
    "http" = uri.scheme
    port = uri.port || 80
    connect(:http, :erlang.binary_to_list(uri.host), port)
  end

  defp connect(:http, host, port) do
    OK.for do
      socket <- :gen_tcp.connect(host, port, [:binary, {:active, true}])
    after
      {:tcp, socket}
    end
  end

  def port({:tcp, socket}) do
    :inet.port(socket)
  end

  def port({:ssl, socket}) do
    {:ok, {_, port}} = :ssl.sockname(socket)
    {:ok, port}
  end

  def negotiated_protocol({:tcp, _socket}) do
    :http1
  end

  def negotiated_protocol({:ssl, socket}) do
    case :ssl.negotiated_protocol(socket) do
      {:ok, "h2"} ->
        :http2

      {:ok, "http/1.1"} ->
        :http1

      {:error, :protocol_not_negotiated} ->
        :http1
    end
  end

  def set_active({:tcp, socket}) do
    :inet.setopts(socket, active: :once)
  end

  def set_active({:ssl, socket}) do
    :ssl.setopts(socket, active: :once)
  end

  def send({:tcp, socket}, message) do
    :gen_tcp.send(socket, message)
  end

  def send({:ssl, socket}, message) do
    :ssl.send(socket, message)
  end
end
