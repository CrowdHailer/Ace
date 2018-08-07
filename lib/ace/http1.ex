defmodule Ace.HTTP1 do
  @moduledoc false

  def serialize_response(status_code, headers, body) do
    [
      "HTTP/1.1 #{status_code} #{Raxx.reason_phrase(status_code)}\r\n",
      header_lines(headers),
      "\r\n",
      body
    ]
  end

  defp header_lines(headers) do
    Enum.map(headers, &header_line/1)
  end

  defp header_line({field_name, field_value}) do
    "#{field_name}: #{field_value}\r\n"
  end
end
