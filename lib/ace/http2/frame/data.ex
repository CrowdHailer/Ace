defmodule Ace.HTTP2.Frame.Data do

  def read(flags, payload) do
    %{padded: padded, end_stream: end_stream} = parse_flags(flags)
    data = if padded do
      Ace.HTTP2.Frame.remove_padding(payload)
    else
      payload
    end

    if end_stream do
      {data, :end}
    else
      {:more, data}
    end
  end

  def parse_flags(<<0::4, padded_flag::1, 0::2, end_stream_flag::1>>) do
    %{
      end_stream: end_stream_flag == 1,
      padded: padded_flag == 1
    }
  end
end
