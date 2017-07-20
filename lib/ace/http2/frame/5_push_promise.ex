defmodule Ace.HTTP2.Frame.PushPromise do
  @enforce_keys [:stream_id, :promised_stream_id, :header_block_fragment]
  defstruct @enforce_keys

  def new(stream_id, promised_stream_id, header_block_fragment) do
    %__MODULE__{
      stream_id: stream_id,
      promised_stream_id: promised_stream_id,
      header_block_fragment: header_block_fragment
    }
  end

  def decode({5, _flags, stream_id, _header_block_fragment}) do
    {:ok, new(stream_id, 0, "TODO")}
  end

  def serialize(frame) do
    length = :erlang.iolist_size(frame.header_block_fragment)
    # TODO flags
    <<length::24, 5::8, 0::8, 0::1, frame.stream_id::31, 0::1, frame.promised_stream_id::31, frame.header_block_fragment::binary>>
  end
end
