defmodule Ace.HTTP2.Frame.Data do
  @enforce_keys [:data, :stream_id, :end_stream]
  defstruct @enforce_keys

  def decode({0, flags, stream_id, payload}) do
    {data, end_stream} = read(flags, payload)
    {:ok, %__MODULE__{data: data, stream_id: stream_id, end_stream: end_stream}}
  end

  def read(flags, payload) do
    %{padded: padded, end_stream: end_stream} = parse_flags(flags)
    data = if padded do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end

    {data, end_stream}
  end

  def parse_flags(<<0::4, padded_flag::1, 0::2, end_stream_flag::1>>) do
    %{
      end_stream: end_stream_flag == 1,
      padded: padded_flag == 1
    }
  end
end
