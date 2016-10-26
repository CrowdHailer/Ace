defmodule Ace.TCP do
  @moduledoc """
  Provide a service over TCP.

  To start an endpoint run `Ace.TCP.start_link/2`.

  Individual TCP connections are handled by the `Ace.TCP.Server` module.
  """

  @doc """
  Start an endpoint linked to the current process.

  See `Ace.TCP.Endpoint` for details of options.
  """

  @spec start_link(app, options) :: {:ok, endpoint} when
    app: Ace.TCP.Server.app,
    endpoint: Ace.TCP.Endpoint.endpoint,
    options: Ace.TCP.Endpoint.options

  def start_link(app, options) do
    Ace.TCP.Endpoint.start_link(app, options)
  end
end
