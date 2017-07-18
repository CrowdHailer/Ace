defmodule HelloHTTP2.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    certfile = Application.app_dir(:hello_http2, "/priv/cert.pem")
    keyfile = Application.app_dir(:hello_http2, "/priv/key.pem")

    options = [
      active: false,
      mode: :binary,
      packet: :raw,
      certfile: certfile,
      keyfile: keyfile,
      reuseaddr: true,
      alpn_preferred_protocols: ["h2", "http/1.1"]
    ]

    {:ok, listen_socket} = :ssl.listen(8443, options)

    children = [
      supervisor(Ace.HTTP2, [listen_socket, {HelloHTTP2, []}])
    ]

    opts = [strategy: :one_for_one, name: HelloHTTP2.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
