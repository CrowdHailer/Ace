defmodule Ace.HTTP2.Stream.RaxxHandler do
  use GenServer
  defmacro __using__(_opts) do
    quote do
      use GenServer
      def start_link(config) do
        GenServer.start_link(unquote(__MODULE__), {:waiting, {__MODULE__, config}})
      end
    end
  end

  def start_link(mod, config) do
    GenServer.start_link(__MODULE__, {:waiting, {mod, config}})
  end

  def handle_info({stream, %{headers: headers, end_stream: end_stream}}, {:waiting, app}) do
    request = Ace.HTTP2.Request.from_headers(headers)
    request = %{request | body: ""}
    handle_request(request, app, stream, end_stream)
  end
  def handle_info({stream, %{data: data, end_stream: end_stream}}, {request, app}) do
    request = %{request | body: request.body <> data}
    handle_request(request, app, stream, end_stream)
  end

  def handle_request(request, app, _stream, false) do
    {:noreply, {request, app}}
  end
  def handle_request(request, app, stream, true) do
    response = dispatch_request(request, app)
    # IO.inspect(response)
    headers = [{":status", "#{response.status}"} | response.headers]
    preface = %{
      headers: headers,
      end_stream: response.body == ""
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
    if response.body != "" do
      data = %{
        data: response.body,
        end_stream: true
      }
      Ace.HTTP2.StreamHandler.send_to_client(stream, data)
    end

    {:noreply, {request, app}}
  end

  def dispatch_request(request, {mod, config}) do
    # TODO enforce_keys on raxx request
    # TODO rename host on raxx
    # TODO replace internal request object with Raxx
    uri = URI.parse(request.path)
    query = Plug.Conn.Query.decode(uri.query || "")
    path = Raxx.Request.split_path(uri.path)
    request = %Raxx.Request{
      scheme: String.to_existing_atom(request.scheme),
      host: request.authority,
      method: String.to_existing_atom(request.method),
      headers: request.headers,
      path: path,
      query: query,
      body: request.body
    }
    mod.handle_request(request, config)
  end
end
