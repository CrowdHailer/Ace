defmodule Ace.HTTP1 do
  @moduledoc false

  def serialize_response(status_code, headers, body) do
    [
      HTTPStatus.status_line(status_code),
      header_lines(headers),
      "\r\n",
      body
    ]
  end

  def pop_chunk(buffer) do
    case String.split(buffer, "\r\n", parts: 2) do
      [base_16_size, rest] ->
        size = base_16_size
        |> :erlang.binary_to_list
        |> :erlang.list_to_integer(16)
        case rest do
          <<chunk::binary-size(size), "\r\n", rest::binary>> ->
            {chunk, rest}
          _incomplete_chunk ->
            {nil, buffer}
        end
      [rest] ->
        {nil, rest}
    end
  end

  @doc """
  Serialize io_data as a single chunk to be streamed.

  ## Example

      iex> Ace.HTTP1.serialize_chunk("hello")
      ...> |> to_string()
      "5\\r\\nhello\\r\\n"

      iex> Ace.HTTP1.serialize_chunk("")
      ...> |> to_string()
      "0\\r\\n\\r\\n"
  """
  def serialize_chunk(data) do
    size = :erlang.iolist_size(data)
    [:erlang.integer_to_list(size, 16), "\r\n", data, "\r\n"]
  end

  defp header_lines(headers) do
    Enum.map(headers, &header_line/1)
  end

  defp header_line({field_name, field_value}) do
    "#{field_name}: #{field_value}\r\n"
  end
end
