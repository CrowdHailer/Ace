defmodule Ace.HTTP1 do
  @moduledoc false

  def serialize_response(response) do
    response = add_message_framing(response)
    [
      HTTPStatus.status_line(response.status),
      header_lines(response.headers),
      "\r\n",
      response.body
    ]
  end

  defp add_message_framing(response) do
    # Always assume no transfer-encoding
    # Best practise to add content-length so that HEAD requests can work
    case {:proplists.get_value("content-length", response.headers), response.body} do
      {length, true} when is_binary(length) ->
        %{response | body: ""}
      {length, _body} when is_binary(length) ->
        response
      {:undefined, false} ->
        headers = [{"content-length", "0"} | response.headers]
        %{response | headers: headers, body: ""}
      {:undefined, body} ->
        content_length = :erlang.iolist_size(body) |> to_string
        headers = [{"content-length", content_length} | response.headers]
        %{response | headers: headers}
    end
  end

  defp header_lines(headers) do
    Enum.map(headers, &header_line/1)
  end

  defp header_line({field_name, field_value}) do
    "#{field_name}: #{field_value}\r\n"
  end
end
