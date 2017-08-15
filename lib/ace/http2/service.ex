defmodule Ace.HTTP2.Service do
  @moduledoc """
  Collection of HTTP/2.0 servers available on a single port.
  """

  alias Ace.HTTP2.{
    Settings
  }

  use Supervisor
  require Logger

  @doc """
  Start an endpoint to accept HTTP/2.0 connections
  """
  def start_link(app, port, opts) do
    case Settings.for_server(Keyword.take(opts, [:max_frame_size])) do
      {:ok, settings} ->
        name = Keyword.get(opts, :name, __MODULE__)
        connections = Keyword.get(opts, :connections, 100)
        {:ok, supervisor} = Supervisor.start_link(__MODULE__, {app, port, opts, settings}, name: name)

        for _index <- 1..connections do
          Supervisor.start_child(supervisor, [])
        end
        {:ok, supervisor}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def init({app, port, opts, settings}) do
    {:ok, certfile} = Keyword.fetch(opts, :certfile)
    {:ok, keyfile} = Keyword.fetch(opts, :keyfile)

    tls_options = [
      active: false,
      mode: :binary,
      packet: :raw,
      certfile: certfile,
      keyfile: keyfile,
      reuseaddr: true,
      alpn_preferred_protocols: ["h2", "http/1.1"]
    ]
    {:ok, listen_socket} = :ssl.listen(port, tls_options)
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    Logger.debug("Listening to port: #{port}")
    if owner = Keyword.get(opts, :owner) do
      send(owner, {:listening, self(), port})
    end

    children = [
      worker(Ace.HTTP2.Server, [listen_socket, app, settings], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one, max_restarts: 1_000)
  end
end
