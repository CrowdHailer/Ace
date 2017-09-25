defmodule HelloHTTP2.WWW do
  use Raxx.Server
  # TODO static

  def handle_headers(_request, greeting) do
    # TODO add content length
    Raxx.response(:ok)
    |> Raxx.set_body(greeting)
  end

  def handle_fragment(_, state) do
    {[], state}
  end
  
  def handle_trailers(_, state) do
    {[], state}
  end
end
