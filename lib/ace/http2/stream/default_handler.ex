defmodule Ace.HTTP2.Stream.DefaultHandler do
  use Ace.HTTP2.Stream

  def handle_info({:headers, request}, {connection, config}) do
    Ace.HTTP2.send_to_client(connection, {
      :headers,
      %{:status => 404, "content-length" => "0"}
    })
    Ace.HTTP2.send_to_client(connection, {
      :data,
      {"", :end}
    })
    {:noreply, {connection, config}}
  end
end
