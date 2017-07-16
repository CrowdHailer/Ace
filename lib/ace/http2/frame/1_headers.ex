defmodule Ace.HTTP2.Frame.Headers do
  @enforce_keys [:stream_id, :header_block_fragment, :end_headers, :end_stream]
  defstruct @enforce_keys

  def new(stream_id, header_block_fragment, end_headers, end_stream) do
    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers,
      end_stream: end_stream,
    }
  end

  def decode({1, flags, stream_id, payload}) do
    <<_::1, _::1, priority::1, _::1, padded::1, end_headers::1, _::1, end_stream::1>> = flags

    data = if padded == 1 do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end

    header_block_fragment = if priority == 1 do
      IO.inspect("Ignoring priority")
      <<0::1, _d_stream_id::31, _weight::8, header_block_fragment::binary>> = data
      header_block_fragment
    else
      data
    end

    {:ok, %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers == 1,
      end_stream: end_stream == 1}}
  end

  def serialize(frame) do
    end_stream_flag = if frame.end_stream, do: 1, else: 0
    end_headers_flag = if frame.end_headers, do: 1, else: 0

    length = :erlang.iolist_size(frame.header_block_fragment)
    flags = <<0::5, end_headers_flag::1, 0::1, end_stream_flag::1>>
    <<length::24, 1::8, flags::binary, 0::1, frame.stream_id::31, frame.header_block_fragment::binary>>
  end
end
