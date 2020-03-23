defmodule Ace.HTTP2.Frame.Headers do
  @moduledoc false

  alias Ace.HTTP2.Frame

  @type t :: %__MODULE__{
          stream_id: Frame.stream_id(),
          header_block_fragment: binary,
          end_headers: boolean,
          end_stream: boolean
        }

  # TODO rename header_block_fragment -> fragment
  @enforce_keys [:stream_id, :header_block_fragment, :end_headers, :end_stream]
  defstruct @enforce_keys

  @spec new(Frame.stream_id(), binary, boolean, boolean) :: t()
  def new(stream_id, header_block_fragment, end_headers, end_stream) do
    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: header_block_fragment,
      end_headers: end_headers,
      end_stream: end_stream
    }
  end

  @spec decode({1, Frame.flags(), Frame.stream_id(), binary}) ::
          {:ok, t()} | {:error, {:protocol_error, string}}
  def decode({1, flags, stream_id, payload}) do
    <<_::1, _::1, priority::1, _::1, padded::1, end_headers::1, _::1, end_stream::1>> = flags

    data =
      if padded == 1 do
        Ace.HTTP2.Frame.remove_padding(payload)
      else
        payload
      end

    if priority == 1 do
      <<_exclusive::1, d_stream_id::31, _weight::8, header_block_fragment::binary>> = data

      if stream_id == d_stream_id do
        {:error, {:protocol_error, "Headers frame can not be dependent on own stream"}}
      else
        {:ok, header_block_fragment}
      end
    else
      {:ok, data}
    end
    |> case do
      {:ok, header_block_fragment} ->
        {
          :ok,
          %__MODULE__{
            stream_id: stream_id,
            header_block_fragment: header_block_fragment,
            end_headers: end_headers == 1,
            end_stream: end_stream == 1
          }
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec serialize(t()) :: binary
  def serialize(frame) do
    end_stream_flag = if frame.end_stream, do: 1, else: 0
    end_headers_flag = if frame.end_headers, do: 1, else: 0

    length = :erlang.iolist_size(frame.header_block_fragment)
    flags = <<0::5, end_headers_flag::1, 0::1, end_stream_flag::1>>

    <<
      length::24,
      1::8,
      flags::binary,
      0::1,
      frame.stream_id::31,
      frame.header_block_fragment::binary
    >>
  end

  defimpl Inspect, for: Ace.HTTP2.Frame.Headers do
    def inspect(%{stream_id: stream_id, end_headers: end_headers, end_stream: end_stream}, _opts) do
      "HEADERS(stream_id: #{stream_id}, end_headers: #{end_headers}, end_stream: #{end_stream})"
    end
  end
end
