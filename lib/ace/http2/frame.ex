defmodule Ace.HTTP2.Frame do
  @moduledoc """
  **Basic protocol unit of HTTP/2.**

  All frames begin with a fixed 9-octet header followed by a variable-
  length payload.

  ```txt
  +-----------------------------------------------+
  |                 Length (24)                   |
  +---------------+---------------+---------------+
  |   Type (8)    |   Flags (8)   |
  +-+-------------+---------------+-------------------------------+
  |R|                 Stream Identifier (31)                      |
  +=+=============================================================+
  |                   Frame Payload (0...)                      ...
  +---------------------------------------------------------------+
  ```
  """

  @data 0
  @headers 1
  @priority 2
  @rst_stream 3
  @settings 4
  @push_promise 5
  @ping 6
  @go_away 7
  @window_update 8
  @continuation 9

  @type stream_id :: 1..31
  @type flags :: <<_::8>>

  @type t ::
          __MODULE__.Data.t()
          | __MODULE__.Headers.t()
          | __MODULE__.Priority.t()
          | __MODULE__.RstStream.t()
          | __MODULE__.Settings.t()
          | __MODULE__.PushPromise.t()
          | __MODULE__.Ping.t()
          | __MODULE__.GoAway.t()
          | __MODULE__.WindowUpdate.t()
          | __MODULE__.Continuation.t()
          | {:unknown_frame_type, integer}

  @spec parse(binary(), max_length: binary) ::
          {:ok, {t | nil, binary}}
          | {
              :error,
              :bad_settings_frame
              | {:flow_control_error, <<_::184>>}
              | {:frame_size_error, <<_::64, _::_*8>>}
              | {:protocol_error, <<_::64, _::_*8>>}
            }
  def parse(buffer, max_length: max_length) do
    case parse_from_buffer(buffer, max_length: max_length) do
      {:ok, {nil, unprocessed}} ->
        {:ok, {nil, unprocessed}}

      {:ok, {raw_frame, unprocessed}} ->
        case decode(raw_frame) do
          {:ok, frame} ->
            {:ok, {frame, unprocessed}}

          # TODO decode return unknown frame
          {:error, {:unknown_frame_type, type}} ->
            {:ok, {{:unknown_frame_type, type}, unprocessed}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_from_buffer(<<length::24, _::binary>>, max_length: max_length)
       when length > max_length do
    {:error, {:frame_size_error, "Frame greater than max allowed: (#{length} >= #{max_length})"}}
  end

  defp parse_from_buffer(
         <<
           length::24,
           type::8,
           flags::bits-size(8),
           _::1,
           stream_id::31,
           payload::binary-size(length),
           rest::binary
         >>,
         max_length: max_length
       )
       when length <= max_length do
    {:ok, {{type, flags, stream_id, payload}, rest}}
  end

  defp parse_from_buffer(buffer, max_length: _) when is_binary(buffer) do
    {:ok, {nil, buffer}}
  end

  def decode(parsed_frame)
  def decode(frame = {@data, _, _, _}), do: __MODULE__.Data.decode(frame)
  def decode(frame = {@headers, _, _, _}), do: __MODULE__.Headers.decode(frame)
  def decode(frame = {@priority, _, _, _}), do: __MODULE__.Priority.decode(frame)
  def decode(frame = {@rst_stream, _, _, _}), do: __MODULE__.RstStream.decode(frame)
  def decode(frame = {@settings, _, _, _}), do: __MODULE__.Settings.decode(frame)
  def decode(frame = {@push_promise, _, _, _}), do: __MODULE__.PushPromise.decode(frame)
  def decode(frame = {@ping, _, _, _}), do: __MODULE__.Ping.decode(frame)
  def decode(frame = {@go_away, _, _, _}), do: __MODULE__.GoAway.decode(frame)
  def decode(frame = {@window_update, _, _, _}), do: __MODULE__.WindowUpdate.decode(frame)
  def decode(frame = {@continuation, _, _, _}), do: __MODULE__.Continuation.decode(frame)
  def decode({type, _, _, _}), do: {:error, {:unknown_frame_type, type}}

  @doc """
  Transform HTTP2 frame to binary that can be transmitted over connection
  """
  def serialize(http2_frame)
  def serialize(frame = %__MODULE__.Data{}), do: __MODULE__.Data.serialize(frame)
  def serialize(frame = %__MODULE__.Headers{}), do: __MODULE__.Headers.serialize(frame)
  def serialize(frame = %__MODULE__.Priority{}), do: __MODULE__.Priority.serialize(frame)
  def serialize(frame = %__MODULE__.RstStream{}), do: __MODULE__.RstStream.serialize(frame)
  def serialize(frame = %__MODULE__.Settings{}), do: __MODULE__.Settings.serialize(frame)
  def serialize(frame = %__MODULE__.PushPromise{}), do: __MODULE__.PushPromise.serialize(frame)
  def serialize(frame = %__MODULE__.Ping{}), do: __MODULE__.Ping.serialize(frame)
  def serialize(frame = %__MODULE__.GoAway{}), do: __MODULE__.GoAway.serialize(frame)
  def serialize(frame = %__MODULE__.WindowUpdate{}), do: __MODULE__.WindowUpdate.serialize(frame)
  def serialize(frame = %__MODULE__.Continuation{}), do: __MODULE__.Continuation.serialize(frame)

  @doc """
  Add padding to a frames data
  """
  def pad_data(data, optional_pad_length)

  def pad_data(data, nil) do
    data
  end

  def pad_data(data, pad_length) when pad_length < 256 do
    bit_pad_length = pad_length * 8
    <<pad_length, data::binary, 0::size(bit_pad_length)>>
  end

  @doc """
  Remove the padding from the payload of a frame
  """
  def remove_padding(<<pad_length, rest::binary>>) do
    rest_length = :erlang.iolist_size(rest)
    data_length = rest_length - pad_length
    bit_pad_length = pad_length * 8
    <<data::binary-size(data_length), 0::size(bit_pad_length)>> = rest
    data
  end
end
