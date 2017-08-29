defmodule Ace.HTTP2.Worker do
  @moduledoc false

  use GenServer

  def start_link({mod, config}) do
    GenServer.start_link(__MODULE__, {mod, config, nil}, [])
  end

  def handle_info({stream, request = %Raxx.Request{}}, {module, state, nil}) do
    module.handle_headers(request, state)
    |> handle_return({module, state, stream})
  end

  def handle_info({stream, %{data: body, end_stream: end_stream}}, {module, state, stream}) do
    module.handle_fragment(body, state)
    |> handle_return({module, state, stream})
    |> case do
      {:noreply, {module, state, stream}} ->
        if end_stream do
          module.handle_trailers([], state)
          |> handle_return({module, state, stream})
        else
          {:noreply, {module, state, stream}}
        end
    end
  end

  def handle_info({stream, {:reset, reason}}, {module, state, stream}) do
    IO.inspect("quiting because: #{inspect(reason)}")
    {:stop, :normal, {module, state, stream}}
  end

  def handle_info(other, {module, state, stream}) do
    module.handle_info(other, state)
    |> handle_return({module, state, stream})
  end

  def handle_return(response = %Raxx.Response{}, {module, state, stream}) do
    # TODO close here
    handle_return({[response], state}, {module, state, stream})
  end
  def handle_return({messages, new_state}, {module, state, stream}) do
    send_messages(messages, stream)
    {:noreply, {module, new_state, stream}}
  end

  def send_messages(messages, stream) do
    Enum.each(messages, &send_it(&1, stream))
  end

  def send_it(r = %Raxx.Response{}, stream) do
    response = struct(Ace.Response, [status: r.status, headers: r.headers, body: r.body])
    Ace.HTTP2.Server.send_response(stream, response)
  end
  def send_it(r = %{data: data, end_stream: end_stream}, stream) do
    Ace.HTTP2.Server.send_data(stream, data, end_stream)
  end
end
