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

  def start_link({mod, config}) do
    start_link(mod, config)
  end
  def start_link(mod, config) do
    GenServer.start_link(__MODULE__, {:waiting, {mod, config}})
  end

  def handle_info({stream, request = %Ace.Request{}}, {:waiting, app}) do
    handle_request(%{request | body: ""}, app, stream, !request.body)
  end
  def handle_info({stream, %{data: data, end_stream: end_stream}}, {request, app}) do
    request = %{request | body: request.body <> data}
    handle_request(request, app, stream, end_stream)
  end
  def handle_info({stream, %{headers: trailers, end_stream: end_stream}}, {request, app}) do
    IO.puts("Dropping trailers #{inspect(trailers)}")
    handle_request(request, app, stream, end_stream)
  end
  def handle_info({_, {:reset, _reason}}, state) do
    {:stop, state, :normal}
  end

  def handle_request(request, app, _stream, false) do
    {:noreply, {request, app}}
  end
  def handle_request(request, app, stream, true) do
    length = :erlang.iolist_size(request.body)
    content_length = case :proplists.get_value("content-length", request.headers) do
      :undefined ->
        :undefined
      content_length ->
        # DEBT add to h2spec a test which sends correct content length.
        # This is currently tested in raxx_test `optional headers are added to request`
        {content_length, ""} = Integer.parse(content_length)
        content_length
    end

    # DEBT allow content_length for empty body,
    # Needs h2spec
    if content_length == :undefined || content_length == length do
      response = dispatch_request(request, app)
      # TODO handle response with empty body
      Ace.HTTP2.Server.send_response(stream, response)

      {:noreply, {request, app}}
    else
      Ace.HTTP2.Server.send_reset(stream, :protocol_error)
      {:stop, :normal, {request, app}}
    end
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
