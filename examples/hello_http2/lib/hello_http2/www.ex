defmodule HelloHTTP2.WWW do
  use Raxx.Server
  # TODO static

  @impl Raxx.Server
  def handle_request(_request, greeting) do
    # TODO add content length
    Raxx.response(:ok)
    |> Raxx.set_body(greeting)
  end

  @impl Raxx.Server
  def handle_tail(_headers, {request, body, state}) do
    handle_request(%{request | body: body}, state)
  end

end
