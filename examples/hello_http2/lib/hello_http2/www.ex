defmodule HelloHTTP2.WWW do
  use Ace.HTTP.Service
  use Raxx.Static, "./public"

  @impl Raxx.Server
  def handle_request(_request, greeting) do
    Raxx.response(:ok)
    |> Raxx.set_body(greeting)
  end

end
