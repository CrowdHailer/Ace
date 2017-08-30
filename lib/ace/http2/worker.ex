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

  def handle_info({stream, %{headers: trailers, end_stream: true}}, {module, state, stream}) do
    module.handle_trailers(trailers, state)
    |> handle_return({module, state, stream})
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

  def send_it(response = %Raxx.Response{}, stream) do
    Ace.HTTP2.send(stream, response)
  end
  def send_it(fragment = %Raxx.Fragment{}, stream) do
    Ace.HTTP2.send(stream, fragment)
  end
  def send_it(trailer = %Raxx.Trailer{}, stream) do
    Ace.HTTP2.send(stream, trailer)
  end
  def send_it({:promise, request}, stream) do
    request = request
    |> Map.put(:scheme, request.scheme || :https)
    Ace.HTTP2.Server.send_promise(stream, request)
  end
end
