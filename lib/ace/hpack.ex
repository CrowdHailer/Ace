defmodule Ace.HPack do
  def new_context(table_size) do
    :hpack.new_context(table_size)
  end

  def encode(headers, context) do
    :hpack.encode(headers, context)
  end

  def decode(header_block, context) do
    :hpack.decode(header_block, context)
  end
end
