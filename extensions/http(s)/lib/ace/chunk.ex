# TODO this module should not exist,
# functionality to be moved to private function in handler
defmodule Ace.Chunk do
  @moduledoc """
  Single part of a chunked response.
  """
  # Ace.Chunk{data: data}

  @doc """
  Serialize io_data as a single chunk to be streamed.

  ## Example

      iex> Ace.Chunk.serialize("hello")
      ...> |> to_string()
      "5\\r\\nhello\\r\\n"

      iex> Ace.Chunk.serialize("")
      ...> |> to_string()
      "0\\r\\n\\r\\n"
  """
  def serialize(data) do
    size = :erlang.iolist_size(data)
    [:erlang.integer_to_list(size, 16), "\r\n", data, "\r\n"]
  end
end
