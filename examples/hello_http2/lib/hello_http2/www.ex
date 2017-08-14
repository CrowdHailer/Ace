defmodule HelloHTTP2.WWW do
  use Ace.Raxx.Handler
  alias Raxx.Response
  require Raxx.Static

  Raxx.Static.serve_dir("./public")

  def handle_request(request, _) do
    Response.ok("Hello, World!", [{"content-length", "13"}])
  end
end
