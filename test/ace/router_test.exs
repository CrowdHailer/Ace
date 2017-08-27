
defmodule SendMessage do
  # Ace server runs lots of Raxx.Servers
  # use Raxx.Server
  # use Raxx.Application
  # Ace.Worker == Raxx.Server

  # handle_commence
  # handle_conclude

  # handle_headers
  # handle_trailers

  def handle_request(request, config) do
    {[], {config, ""}}
  end

  def handle_fragment(data, {config, buffer}) do
    {[], {config, buffer <> data}}
  end

  def handle_completion(_trailers, {config, body}) do
    IO.inspect(config)
    IO.inspect(body)
    Ace.Response.new(201, [], false)
  end
end

defmodule Ace.BluePrint do
  def split_path(path_string) do
    path_string
    |> String.split("/")
    |> Enum.reject(&empty_string?/1)
  end

  defp empty_string?("") do
    true
  end
  defp empty_string?(str) when is_binary(str) do
    false
end

  defmacro __using__(parsed) do
    actions = Enum.flat_map(parsed, fn({path, actions}) ->
      Enum.map(actions, fn({method, module}) ->
        {method, path, module}
      end)
    end)

    # IO.inspect(actions)

    infos = for {method, path, module} <- actions do
      [path | _] = String.split(path, "?")
      [path | _] = String.split(path, "#")
      segments = split_path(path)

      path_match = segments |> Enum.map(fn(segment) ->
        case String.split(segment, ~r/[{}]/) do
          [raw] ->
            raw
          ["", _name, ""] ->
            Macro.var(:_, nil)
        end
      end)
      |> IO.inspect

      # TODO needs to
      quote do
        def handle_info({stream, request = %Ace.Request{method: unquote(method), path: unquote(path_match)}}, config) do
          unquote(module).handle_request(request, config)
          |> handle_return(stream, {unquote(module), config})

        end
      end
    end

    quote do
      use GenServer

      def start_link(config) do
        GenServer.start_link(__MODULE__, config, [])
      end

      unquote(infos)

      def handle_info({stream, %{data: body, end_stream: end_stream}}, {module, state}) do
        module.handle_fragment(body, state)
        |> handle_return(stream, {module, state})
        |> case do
          {:noreply, {module, state}} ->
            if end_stream do
              module.handle_completion([], state)
              |> handle_return(stream, {module, state})
            else
              {:noreply, {module, state}}
            end
        end
      end

      # message is list, response, fragment, trailer, flow control promise
      def handle_return(response = %Ace.Response{}, stream, {module, state}) do
        handle_return({[response], state}, stream, {module, state})
      end
      def handle_return({messages, new_state}, stream, {module, _old_state}) do
        send_messages(messages, stream)
        {:noreply, {module, new_state}}
      end

      def send_messages(messages, stream) do
        Enum.each(messages, &send_it(&1, stream))
      end

      def send_it(r = %Ace.Response{}, stream) do
        Ace.HTTP2.Server.send_response(stream, r)
      end
    end

  end
end

defmodule WWW do

  use Ace.BluePrint, [
    {"/", [GET: HomePage, POST: SendMessage]},
    {"/hi/{name}", [GET: Greeting]}
  ]
end

defmodule Ace.RouterTest do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Client,
    Service
  }

  @tag :skip
  test "check Raxx streaming API" do
    opts = [port: 0, owner: self(), certfile: Support.test_certfile(), keyfile: Support.test_keyfile()]
    assert {:ok, service} = Service.start_link({WWW, [:config]}, opts)
    assert_receive {:listening, ^service, port}

    {:ok, client} = Client.start_link({"localhost", port})
    {:ok, client_stream} = Client.stream(client)

    request = Ace.Request.post("/", [{"content-type", "text/plain"}], true)
    :ok = Client.send_request(client_stream, request)
    :ok = Client.send_data(client_stream, "Hello,", false)
    :ok = Client.send_data(client_stream, " World!", true)

    assert_receive {^client_stream, received = %Ace.Response{}}, 1_000
    assert 201 == received.status

    {:ok, client_stream2} = Client.stream(client)
    request = Ace.Request.get("/hi/peter", [{"content-type", "text/plain"}])
    :ok = Client.send_request(client_stream2, request)

    assert_receive {^client_stream, received = %Ace.Response{}}, 1_000
    assert 201 == received.status

  end
end
