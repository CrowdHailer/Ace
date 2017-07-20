defmodule Ace.HTTP2.Stream.DefaultHandler do

  def handle_info({stream, _}, state) do
    headers = %{
      ":status" => "404",
      "content-length" => "0"
    }
    preface = %{
      headers: headers,
      end_stream: true
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
    {:noreply, state}
  end
end
