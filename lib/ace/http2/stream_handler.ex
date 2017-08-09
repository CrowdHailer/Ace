# Can pass in a supervisor that has router and config preset
# then can blindly start worker and forward messages or find pid for client
defmodule Ace.HTTP2.StreamHandler do
  @moduledoc false
  use GenServer
  def start_link(config, router) do
    GenServer.start_link(__MODULE__, {config, router})
  end

  def handle_info({stream, request}, {config, router}) do
    # DEBT try/catch assume always returns check with dialyzer
    handler = try do
      router.route(request)
    rescue
      _exception in FunctionClauseError ->
      # TODO implement DefaultHandler
      Ace.HTTP2.Stream.DefaultHandler
    end
    case handler.handle_info({stream, request}, config) do
      {:noreply, state} ->
        :gen_server.enter_loop(handler, [], state)
    end
  end
end
