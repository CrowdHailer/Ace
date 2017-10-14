defmodule Ace.HTTP2.Service do
  @moduledoc """
  Serve a `Raxx.Server` application over HTTP/2.

  ## Hello World

  *Server specification*
      defmodule MyProject.WWW do
        use Raxx.Server

        def handle_headers(%Raxx.Request{method: :GET, path: []}, greeting) do
          Raxx.response(:ok)
          |> Raxx.set_header("content-type", "text/plain")
          |> Raxx.set_body(greeting)
        end
      end

  *Server startup*
      application = {MyProject.WWW, "Hello, World!"}

      options = [
        port: 8443,
        certfile: "path/to/certfile"
        keyfile: "path/to/keyfile"
      ]
      {:ok, pid} = Ace.HTTP2.Service.start_link(application, options)

  **Ace use the `Raxx.Server` interface to describe server actions,
  see the `Raxx.Server` [documentation](https://hexdocs.pm/raxx/Raxx.Server.html)
  for full details**

  ## Supervised services

  It is best practise start processes in an application supervision tree.
  To supervise an `Ace.HTTP2.Service` start a new mix project with the `--sup` flag

      $ mix new my_project --sup

  Then add one or more service to the projects list of supervised processes
  in `lib/my_project/application.ex`.

      defmodule MyProject.Application do
        use Application

        def start(_type, _args) do
          import Supervisor.Spec, warn: false

          application = {MyProject.WWW, "Hello, World!"}

          options = [
            port: 8443,
            certfile: Application.app_dir(:my_project, "/priv/www/cert.pem")
            keyfile: Application.app_dir(:my_project, "/priv/www/key.pem")
          ]

          # List all child processes to be supervised
          children = [
            supervisor(Ace.HTTP2.Service, [application, options]),
          ]

          # See https://hexdocs.pm/elixir/Supervisor.html
          # for other strategies and supported options
          opts = [strategy: :one_for_one, name: MyProject.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  ## TLS(SSL) credentials

  Ace.HTTP2 only supports using a secure transport layer.
  Therefore a certificate and certificate_key are needed to serve an application.

  For local development a [self signed certificate](http://how2ssl.com/articles/openssl_commands_and_tips/) can be used.

  ##### Note

  Store certificates in a projects `priv` directory if they are to be distributed as part of a release.

  ## Testing endpoints

  Starting a service on port `0` will rely on the operating system to allocate an available port.
  This allows services to be stood up for individual tests, perhaps all with different configuration.

  To find the port that a service has started using a process may be given as the optional owner.
  Once the service has started the owner receives a message with format.

      {:listening, service_pid, port}

  This can be used to setup test services.

      opts = [port: 0, owner: self(), certfile: certfile, keyfile: keyfile]
      assert {:ok, service} = Service.start_link({TestApp, [:test_config]}, opts)
      assert_receive {:listening, ^service, port}

      # Use general purpose client libraries to test service available at `port`

  This can be seen in action in the test directories of this project.
  """

  alias Ace.HTTP2.{Settings}

  use Supervisor
  require Logger

  @doc """
  Start an endpoint to accept HTTP/2.0 connections
  """
  def start_link(application, options) do
    case Settings.for_server(Keyword.take(options, [:max_frame_size])) do
      {:ok, settings} ->
        port = Keyword.get(options, :port, 8443)
        # name = Keyword.get(options, :name, :"#{__MODULE__}:#{port}")
        connections = Keyword.get(options, :connections, 100)

        {:ok, supervisor} =
          Supervisor.start_link(__MODULE__, {application, port, options, settings}, options)

        for _index <- 1..connections do
          Supervisor.start_child(supervisor, [])
        end

        {:ok, supervisor}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## SERVER CALLBACKS

  @doc false
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

    supervise(children, strategy: :simple_one_for_one, max_restarts: 1000)
  end
end
