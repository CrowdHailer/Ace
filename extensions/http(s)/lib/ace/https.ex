defmodule Ace.HTTPS do
  @moduledoc """
  Securely serve a web application from an HTTPS endpoint.

  To start an endpoint use `start_link/2`.

  Compatible web applications are defined using the Raxx specification,
  see documentation for details.

  - [https://hexdocs.pm/raxx](https://hexdocs.pm/raxx)
  """

  @doc """
  Start a secure HTTPS web application.

  ```
  {:ok, pid} = Ace.HTTPS.start_link(my_app, [
    certificate: Application.app_dir(:www, "priv/certificate.pem"),
    certificate_key: Application.app_dir(:www, "priv/key.pem")
  ])
  ```

  A Raxx application is a tuple combining a behaviour module and configuration.
  e.g.

  ```
  my_app = {MyApp, %{config: :my_config}}
  ```

  ## Options

  Options are the same as [`Ace.TLS`](https://hexdocs.pm/ace/Ace.TLS.html).
  """
  def start_link(raxx_application, options \\ []) do
    Ace.TLS.start_link({Ace.HTTP.Handler, raxx_application}, options)
  end

  @doc """
  Fetch the port number of a running endpoint.
  """
  def port(endpoint) do
    Ace.TLS.port(endpoint)
  end
end
