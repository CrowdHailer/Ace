defmodule Ace.HTTP2.Frame.Continuation do
  @enforce_keys [:stream_id, :header_block_fragment, :end_headers]
  defstruct @enforce_keys

  def new(stream_id, header_block_fragment, end_headers) do
    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers
    }
  end

  def decode({9, <<_::5, end_headers_flag::1, _::2>>, stream_id, hbf}) do
    end_headers = case end_headers_flag do
      1 ->
        true
      0 ->
        false
    end
    {:ok, new(stream_id, hbf, end_headers)}
  end

  def serialize(frame) do
    end_headers_flag = if frame.end_headers, do: 1, else: 0

    length = :erlang.iolist_size(frame.header_block_fragment)
    flags = <<0::5, end_headers_flag::1, 0::1, 0::1>>
    <<length::24, 9::8, flags::binary, 0::1, frame.stream_id::31, frame.header_block_fragment::binary>>
  end
end
