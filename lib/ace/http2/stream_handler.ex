# Can pass in a supervisor that has router and config preset
# then can blindly start worker and forward messages or find pid for client
defmodule Ace.HTTP2.StreamHandler do
  @moduledoc false
  use GenServer
  def start_link(config, router) do
    GenServer.start_link(__MODULE__, {config, router})
  end

  def handle_info({stream, message}, {config, router}) do
    {:ok, request} = Ace.HTTP2.Stream.build_request(message.headers)
    request = %{request | body: !message.end_stream}
    |> IO.inspect
    # DEBT try/catch assume always returns check with dialyzer
    handler = try do
      router.route(request)
    rescue
      _exception in FunctionClauseError ->
      # TODO implement DefaultHandler
      Ace.HTTP2.Stream.DefaultHandler
    end
    case handler.handle_info({stream, message}, config) do
      {:noreply, state} ->
        :gen_server.enter_loop(handler, [], state)
    end
  end

  def send_to_client({:stream, pid, id, ref}, message) do
    send(pid, {{:stream, id, ref}, message})
  end
end
