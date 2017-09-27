defmodule Ace.Service do
  @moduledoc """


                      (service)

  (governor_supervisor) (server_supervisor) (worker_supervisor)
  OR
  (governor_supervisor) (connection_supervisor) (server_supervisor)
  OR
  (governor_supervisor) (endpoint_supervisor) (server_supervisor)

                            (server) <- endpoint

  (governor_supervisor) (connection_supervisor) (worker_supervisor)

  connection -> portal
  worker -> exchange -> stream

  Ace.Client
  An HTTP "client" is a program that establishes a connection to a server for the purpose of sending one or more HTTP requests.
  A clients channel is started with configuration that includes a recipient/worker

  I think drop TCP level being exposed.

  Ace.Service
  Starts many Ace.Server

  Ace.Server
  Uses Ace.HTTP.Endpoint.init(:server)

  if not given a worker supervisor it will start one using a specification.

  children = [
    Ace.
  ]

  """
  use Supervisor

  def start_link({module, config}, port, options) do
    # Does module implement Raxx.Worker?

    # start socket send message to owner
    listen_socket = :ls

    children = [
      supervisor(Ace.RaxxWorkerSupervisor, [{module, config}, []]),
      # This needs to start a tls or tcp thing
      supervisor(Ace.EndpointSupervisor, [{Ace.HTTP.Endpoint, Ace.RaxxWorkerSupervisor}])
    ]
  end

  # don't use supervisor user GenServer as allows pids to be passed to each other
  # OR just start as part of application set up

  @doc """
  children = [
    supervisor(Ace.WorkerSupervisor, [{module, config}, [name: WWW.WorkerSupervisor]]),
    supervisor(Ace.EndpointSupervisor, [Ace.WorkerSupervisor, [name: WWW.EndpointSupervisor]]),
    supervisor(Ace.GovernorSupervisor, [Ace.EndpointSupervisor, socket, [acceptors: 100, name: WWW.GovernorSupervisor]]),
    # Can repeat this line 10 times over each pointing to different WorkerSupervisor if trouble starting up in time.
  ]

  # See https://hexdocs.pm/elixir/Supervisor.html
  # for other strategies and supported options
  opts = [strategy: :one_for_one, name: MyProject.Supervisor]
  Supervisor.start_link(children, opts)
  """

  def start_link({module, config}, port, options) do
    # start connection
    Ace.RaxxWorker.Supervisor.start_link({module, config})
    Ace.HTTP.EndpointSupervisor.start
  end
end
