defmodule Ace.HTTP.ResponseTest do
  use Raxx.Verify.ResponseCase

  import ExUnit.CaptureLog, only: [capture_log: 1]

  setup do
    raxx_app = {__MODULE__, %{target: self()}}
    capture_log fn() ->
      {:ok, endpoint} = Ace.HTTP.start_link(raxx_app, port: 0)
      {:ok, port} = Ace.HTTP.port(endpoint)
      send(self(), {:port, port})
    end
    port = receive do
      {:port, port} -> port
    end
    {:ok, %{port: port}}
  end

end
