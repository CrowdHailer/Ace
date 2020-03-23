defmodule Ace.HTTP2.Frame.PushPromise do
  @moduledoc false
  alias Ace.HTTP2.Frame

  @type t :: %__MODULE__{
          stream_id: Frame.stream_id(),
          promised_stream_id: Frame.stream_id(),
          header_block_fragment: binary,
          end_headers: boolean
        }

  @enforce_keys [:stream_id, :promised_stream_id, :header_block_fragment, :end_headers]
  defstruct @enforce_keys

  @spec new(Frame.stream_id(), Frame.stream_id(), binary, boolean) :: t()
  def new(stream_id, promised_stream_id, header_block_fragment, end_headers) do
    %__MODULE__{
      stream_id: stream_id,
      promised_stream_id: promised_stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers
    }
  end

  @spec decode({5, binary, Frame.stream_id(), binary}) :: {:ok, t()}
  def decode({5, flags, stream_id, payload}) do
    <<_::4, padded::1, end_headers::1, _::2>> = flags
    end_headers = end_headers == 1

    data =
      if padded == 1 do
        Ace.HTTP2.Frame.remove_padding(payload)
      else
        payload
      end

    <<_R::1, promised_stream_id::31, header_block_fragment::binary>> = data

    {:ok, new(stream_id, promised_stream_id, header_block_fragment, end_headers)}
  end

  @spec serialize(t()) :: binary
  def serialize(frame) do
    length = 4 + byte_size(frame.header_block_fragment)
    # DEBT provide way to serialize with padding
    padded_flag = 0
    end_headers_flag = if frame.end_headers, do: 1, else: 0
    flags = <<0::4, padded_flag::1, end_headers_flag::1, 0::2>>

    <<
      length::24,
      5::8,
      flags::binary,
      0::1,
      frame.stream_id::31,
      0::1,
      frame.promised_stream_id::31,
      frame.header_block_fragment::binary
    >>
  end

  defimpl Inspect, for: Ace.HTTP2.Frame.PushPromise do
    def inspect(
          %{
            stream_id: stream_id,
            promised_stream_id: promised_stream_id,
            end_headers: end_headers
          },
          _opts
        ) do
      "PUSH_PROMISE(stream_id: #{stream_id}, promised_stream_id: #{promised_stream_id}, end_headers: #{
        end_headers
      })"
    end
  end
end
