defmodule MyApp.WWW.WatchUpdates do
  use Raxx

  # Maybe a different name to not get confused with handle_request/2
  def handle_request(request, _, config) do
    response = case Request.accept?(request, "text/event-stream") do
      true ->
        ChatRoom.join(config.room)
        Response.new(:ok, [{"content-type", "text/event-stream"}], true)
      false ->
        # not acceptable
    end

    {response, config}
  end

  def handle_info({ChatRoom, data}, state) do
    data = ServerSentEvent.serialize(%ServerSentEvent{lines: [data], type: "chat"})
    fragment = Fragment.new(data)
    {fragment, state}
  end

  def terminate(_reason, _config) do
    # called when connection closes
    exit(:normal)
  end
end

defmodule Router do
  def handle_request(request, connection, config) do
    case {request.method, request.path} do
      {:GET, []}
        Module1.handle_request(request, connection, {Module1, config})
    end
  end

  def handle_info(message, {Module1, config}) do
    Module1.handle_info(message, config)
  end
end

defmodule HomePage do
  use Raxx.Unary, max_body: 0

  EEx.function_from_file(:defp, :home_page, Path.join(__DIR__, "./templates/home_page.html.eex"), [])

  def handle_request(request, config) do
    body = home_page()
    Ace.Response.new(200, [], body)
  end
end
