defmodule Ace.HTTP2.Service do
  @moduledoc """
  Run a supervised tree of HTTP/2.0 servers, all available on a single port.

  A behaviour of an `Ace.HTTP2.Service` is defined by the application it runs.

  Example application:

      defmodule MyProject.WWW do
        def start_link(greeting) do
          GenServer.start_link(__MODULE__, greeting)
        end

        def handle_info({stream, %Ace.Request{method: :GET, path: "/"}}, greeting) do
          response = Ace.Response.new(200, [], greeting)
          Ace.HTTP2.Server.send_response(stream, response)
        end
        def handle_info({stream, _request}, _state) do
          response = Ace.Response.new(404, [], false)
          Ace.HTTP2.Server.send_response(stream, response)
        end
      end

  - *See `Ace.HTTP2.Server` for all functionality available to a stream worker.*
  - *See `Ace.Raxx.Handler` for help with a concise stream worker.*

  This module has a `start_link/1` function and so can be started by as a service as follows.

      application = {MyProject.WWW, ["Hello, World!"]}
      options = [
        port: 8443,
        certfile: "path/to/certfile"
        keyfile: "path/to/keyfile"
      ]

      {:ok, pid} = Ace.HTTP2.Service.start_link(application, options)

  - *See `start_link/2` for the full list of options available when starting a service*

  Each client request defines an independant stream.
  Each stream is handled by an isolated worker process running the application.

  ## Supervising services

  Ace makes it easy to start multiple services in a single Mix project.
  Starting a service returns the service supervisor.

  This supervisor may act as the application supervisor if it is the only one started.

      defmodule MyProject.Application do
        @moduledoc false

        use Application

        def start(_type, _args) do

          certfile = Application.app_dir(:my_project, "/priv/cert.pem")
          keyfile = Application.app_dir(:my_project, "/priv/key.pem")

          Ace.HTTP2.Service.start_link(
            {MyProject.WWW, ["Hello, World!"]},
            port: 8443,
            certfile: certfile,
            keyfile: keyfile
          )
        end
      end

  An `Ace.HTTP2.Service` can also exist as one of a group of supervisors.

      defmodule MyProject.Application do
        @moduledoc false

        use Application

        def start(_type, _args) do
          import Supervisor.Spec, warn: false

          www_certfile = Application.app_dir(:my_project, "/priv/www/cert.pem")
          www_keyfile = Application.app_dir(:my_project, "/priv/www/key.pem")

          www_app = {MyProject.WWW, ["Hello, World!"]}
          www_opts = [port: 8443, certfile: www_certfile, keyfile: www_keyfile]

          api_certfile = Application.app_dir(:my_project, "/priv/api/cert.pem")
          api_keyfile = Application.app_dir(:my_project, "/priv/api/key.pem")

          api_app = {MyProject.WWW, ["Hello, World!"]}
          api_opts = [port: 8443, certfile: api_certfile, keyfile: api_keyfile]

          children = [
            supervisor(Ace.HTTP2.Service, [www_app, www_opts]),
            supervisor(Ace.HTTP2.Service, [api_app, api_opts]),
            worker(MyProject.worker, [arg1, arg2, arg3]),
          ]
        end
      end

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

  alias Ace.HTTP2.{
    Settings
  }

  use Supervisor
  require Logger

  @doc """
  Start an endpoint to accept HTTP/2.0 connections
  """
  def start_link(application, options) do
    case Settings.for_server(Keyword.take(options, [:max_frame_size])) do
      {:ok, settings} ->
        name = Keyword.get(options, :name, __MODULE__)
        port = Keyword.get(options, :port, 8443)
        connections = Keyword.get(options, :connections, 100)
        {:ok, supervisor} = Supervisor.start_link(__MODULE__, {application, port, options, settings}, name: name)

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
    supervise(children, strategy: :simple_one_for_one, max_restarts: 1_000)
  end
end
