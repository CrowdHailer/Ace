defmodule Ace.HPack do
  @moduledoc false

  @type context :: :hpack.context()

  @spec new_context(non_neg_integer()) :: context()
  def new_context(table_size) do
    :hpack.new_context(table_size)
  end

  @spec encode(Raxx.headers(), context()) :: {:ok, {binary, context()}} | {:error, any}
  def encode(headers, context) do
    :hpack.encode(headers, context)
  end

  @spec decode(binary, context()) ::
          {:ok, {Raxx.headers(), context()}}
          | {:error, :compression_error}
          | {:error, {:compression_error, {:bad_header_packet, binary}}}
  def decode(header_block, context) do
    :hpack.decode(header_block, context)
  end
end
