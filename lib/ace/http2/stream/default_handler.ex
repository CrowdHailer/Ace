defmodule Ace.HTTP2.Stream.DefaultHandler do
  @moduledoc false
  def handle_info({stream, _}, state) do
    response = Ace.Response.new(404, [{"content-length", "0"}], "")
    Ace.HTTP2.Server.send_response(stream, response)
    {:noreply, state}
  end
end
