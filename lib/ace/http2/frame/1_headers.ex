defmodule Ace.HTTP2.Frame.Headers do
  @enforce_keys [:stream_id, :header_block_fragment, :end_headers, :end_stream]
  defstruct @enforce_keys

  def decode({1, flags, stream_id, payload}) do
    <<_::1, _::1, priority::1, _::1, padded::1, end_headers::1, _::1, end_stream::1>> = flags
    IO.inspect(priority)
    IO.inspect(padded)
    IO.inspect(end_headers)
    IO.inspect(end_stream)

    data = if padded == 1 do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end

    header_block_fragment = if priority == 1 do
      <<0::1, stream_id::31, weight::8, header_block_fragment::binary>> = data
      IO.inspect(stream_id)
      IO.inspect(weight)
      header_block_fragment
    else
      data
    end

    {:ok, %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers,
      end_stream: end_stream}}
  end
end
