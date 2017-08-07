defmodule Ace.HTTP2.Frame.PushPromise do
  @moduledoc false
  @enforce_keys [:stream_id, :promised_stream_id, :header_block_fragment, :end_headers]
  defstruct @enforce_keys

  def new(stream_id, promised_stream_id, header_block_fragment, end_headers) do
    %__MODULE__{
      stream_id: stream_id,
      promised_stream_id: promised_stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers
    }
  end

  def decode({5, flags, stream_id, payload}) do
    <<_::4, padded::1, end_headers::1, _::2>> = flags
    end_headers = end_headers == 1

    data = if padded == 1 do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end

    <<_R::1, promised_stream_id::31, header_block_fragment::binary>> = data

    {:ok, new(stream_id, promised_stream_id, header_block_fragment, end_headers)}
  end

  def serialize(frame) do
    length = :erlang.iolist_size(frame.header_block_fragment)
    # TODO flags
    <<length::24, 5::8, 0::8, 0::1, frame.stream_id::31, 0::1, frame.promised_stream_id::31, frame.header_block_fragment::binary>>
  end
end
