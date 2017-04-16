defmodule Ace.Chunk do
  # Ace.Chunk{data: data}
  def serialize(data) do
    size = :erlang.iolist_size(data)
    [:erlang.integer_to_list(size, 16), "\r\n", data, "\r\n"]
  end
end
