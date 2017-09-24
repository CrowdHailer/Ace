defmodule Ace.HTTP1 do
  @moduledoc false

  def serialize_response(response, %{keep_alive: keep_alive}) do
    response = add_message_framing(response)
    response = add_connection_header(response, %{keep_alive: keep_alive})
    [
      HTTPStatus.status_line(response.status),
      header_lines(response.headers),
      "\r\n",
      response.body
    ]
  end

  defp add_connection_header(response = %{headers: headers}, %{keep_alive: false}) do
    if :proplists.is_defined("connection", headers) do
      raise "Should not expose connection state in application"
    end
    headers = [{"connection", "close"} | headers]
    %{response | headers: headers}
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
