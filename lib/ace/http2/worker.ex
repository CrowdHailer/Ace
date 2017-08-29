defmodule Ace.HTTP2.Worker do
  @moduledoc false

  use GenServer

  def start_link(app) do
    GenServer.start_link(__MODULE__, app, [])
  end

  def handle_info({stream, request = %Ace.Request{}}, {module, state}) do
    uri = URI.parse(request.path)
    query = Plug.Conn.Query.decode(uri.query || "")
    path = Raxx.Request.split_path(uri.path)
    request = %Raxx.Request{
      scheme: request.scheme,
      # TODO rename to authority
      host: request.authority,
      method: request.method,
      headers: request.headers,
      path: path,
      query: query,
      body: request.body
    }
    module.handle_headers(request, state)
    |> handle_return(stream, {module, state})
  end

  def handle_info({stream, %{data: body, end_stream: end_stream}}, {module, state}) do
    module.handle_fragment(body, state)
    |> handle_return(stream, {module, state})
    |> case do
      {:noreply, {module, state}} ->
        if end_stream do
          module.handle_trailers([], state)
          |> handle_return(stream, {module, state})
        else
          {:noreply, {module, state}}
        end
    end
  end

  def handle_info(other, {module, state}) do
    module.handle_info(other, state)
    |> handle_return({module, state})
  end

  def handle_return(response = %Raxx.Response{}, stream, {module, state}) do
    handle_return({[response], state}, stream, {module, state})
  end
  def handle_return({messages, new_state}, stream, {module, _old_state}) do
    send_messages(messages, stream)
    {:noreply, {module, new_state}}
  end

  def send_messages(messages, stream) do
    Enum.each(messages, &send_it(&1, stream))
  end

  def send_it(r = %Raxx.Response{}, stream) do
    response = struct(Ace.Response, [status: r.status, headers: r.headers, body: r.body])
    Ace.HTTP2.Server.send_response(stream, response)
  end
end
