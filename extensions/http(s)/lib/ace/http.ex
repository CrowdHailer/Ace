defmodule Ace.HTTP do
  @moduledoc """
  Serve a web application from an HTTP endpoint.
  Running a HTTP server on [Ace](https://hex.pm/packages/ace)

  To start an endpoint use `start_link/2`.

  Compatible web applications are defined using the Raxx specification,
  see documentation for details.

  - [https://hexdocs.pm/raxx](https://hexdocs.pm/raxx)
  """

  @doc """
  Start a HTTP web application.

  ```
  {:ok, pid} = Ace.HTTP.start_link(my_app)
  ```

  A Raxx application is a tuple combining a behaviour module and configuration.
  e.g.

  ```
  my_app = {MyApp, %{config: :my_config}}
  ```

  ## Options

  Options are the same as [`Ace.TCP`](https://hexdocs.pm/ace/Ace.TCP.html).
  """
  def start_link(raxx_app, options \\ []) do
    Ace.TCP.start_link({Ace.HTTP.Handler, raxx_app}, options)
  end

  @doc """
  Fetch the port number of a running endpoint.

  **OS assigned ports:**
  If an endpoint is started with port number `0` it will be assigned a port by the underlying system.
  This can be used to start many endpoints simultaneously.
  It can be useful running parallel tests.
  """
  def port(endpoint) do
    Ace.TCP.port(endpoint)
  end
end
