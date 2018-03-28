defmodule Ace.HTTP2.Frame.Data do
  @moduledoc false

  alias Ace.HTTP2.Frame

  @type t :: %__MODULE__{data: binary}

  @enforce_keys [:data, :stream_id, :end_stream]
  defstruct @enforce_keys

  def new(stream_id, data, end_stream) do
    %__MODULE__{data: data, stream_id: stream_id, end_stream: end_stream}
  end

  @spec decode({0, Frame.flags(), Frame.stream_id(), binary}) :: {:ok, t}
  def decode({0, flags, stream_id, payload}) do
    {data, end_stream} = read(flags, payload)
    {:ok, new(stream_id, data, end_stream)}
  end

  # DEBT handle padding
  def serialize(frame) do
    length = :erlang.iolist_size(frame.data)
    end_stream_flag = if frame.end_stream, do: 1, else: 0
    padded_flag = 0
    flags = <<0::4, padded_flag::1, 0::2, end_stream_flag::1>>
    <<length::24, 0::8, flags::binary, 0::1, frame.stream_id::31, frame.data::binary>>
  end

  def read(flags, payload) do
    %{padded: padded, end_stream: end_stream} = parse_flags(flags)

    data =
      if padded do
        Frame.remove_padding(payload)
      else
        payload
      end

    {data, end_stream}
  end

  def parse_flags(<<_::4, padded_flag::1, _::2, end_stream_flag::1>>) do
    %{
      end_stream: end_stream_flag == 1,
      padded: padded_flag == 1
    }
  end

  defimpl Inspect, for: Frame.Data do
    def inspect(%{data: data, end_stream: end_stream, stream_id: stream_id}, _opts) do
      {preview, rest} = String.split_at(data, 50)
      end_preview = if rest == "", do: "", else: "..."

      "DATA(stream_id: #{stream_id}, end_stream: #{end_stream}, data: #{inspect(preview)}#{
        end_preview
      })"
    end
  end
end
