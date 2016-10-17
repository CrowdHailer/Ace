defmodule Ace.TCP do
  @moduledoc """
  Provide a service over TCP.

  To start an endpoint run `Ace.TCP.start_link/2`.

  Individual TCP connections are handled by `Ace.TCP.Server`.
  """

  @doc """
  start an endpoint with the given options.

  See `Ace.TCP.Endpoint` for details of options.
  """
  def start_link(app, opts) do
    Ace.TCP.Endpoint.start_link(app, opts)
  end
end
