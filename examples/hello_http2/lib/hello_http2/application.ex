defmodule HelloHTTP2.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do

    certfile = Application.app_dir(:hello_http2, "/priv/cert.pem")
    keyfile = Application.app_dir(:hello_http2, "/priv/key.pem")

    service_options = [
      port: 8443,
      certfile: certfile,
      keyfile: keyfile,
      connections: 1_000
    ]
    children = [
      {HelloHTTP2.WWW, ["Hello, World!", service_options]}
    ]

    opts = [strategy: :one_for_one, name: Foo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
