# TODO this module should not exist,
# functionality to be moved to private function in handler
defmodule Ace.Response do
  @moduledoc false
  # This module is not part of the public API.
  # Contained functionalitly is likely to move to the Raxx project.

  # It should be possible just to make this a Chars.to_string implementation
  def serialize(response = %{status: status, headers: headers}) do
    [
      HTTPStatus.status_line(status),
      header_lines(headers),
      "\r\n",
      serialize_body(response)
    ]
  end

  defp header_lines(headers) do
    Enum.map(headers, &header_line/1)
  end

  defp header_line({field_name, field_value}) do
    "#{field_name}: #{field_value}\r\n"
  end

  # Handle a Raxx.Response
  defp serialize_body(%{body: body}) do
    body
  end
  defp serialize_body(%{chunks: chunks}) do
    Enum.map(chunks, &Ace.Chunk.serialize/1)
  end
end
