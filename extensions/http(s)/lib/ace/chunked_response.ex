defmodule Ace.ChunkedResponse do
  defstruct [
    status: nil,
    headers: [],
    app: nil,
    chunks: []
  ]

  def to_iodata(response = %__MODULE__{}) do
    [
      HTTPStatus.status_line(response.status),
      header_lines(response.headers),
      "\r\n"
    ]
  end

  defp header_lines(headers) do
    Enum.map(headers, &header_line/1)
  end

  defp header_line({field_name, field_value}) do
    "#{field_name}: #{field_value}\r\n"
  end
end
