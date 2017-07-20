defmodule Ace.HTTP2 do
  use Supervisor

  def start_link(app, port, opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    connections = Keyword.get(opts, :connections, 100)
    {:ok, supervisor} = Supervisor.start_link(__MODULE__, {app, port, opts}, name: name)

    for _index <- 1..connections do
      Supervisor.start_child(supervisor, [])
    end
    {:ok, supervisor}
  end

  def init({app, port, opts}) do
    # DEBT read name twice
    name = Keyword.get(opts, :name, __MODULE__)
    # server_name = Module.concat(name, Server)
    # stream_supervisor_name = Module.concat(name, Stream.Supervisor)

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

    children = [
      worker(Ace.HTTP2.Connection, [listen_socket, app], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end
