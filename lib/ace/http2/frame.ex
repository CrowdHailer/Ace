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

  @doc """
  Read the next available frame.
  """
  def parse_from_buffer(
    <<
      length::24,
      type::8,
      flags::bits-size(8),
      0::1,
      stream_id::31,
      payload::binary-size(length),
      rest::binary
    >>)
  do
    {{type, flags, stream_id, payload}, rest}
  end
  def parse_from_buffer(buffer) when is_binary(buffer) do
    {nil, buffer}
  end

  def pad_data(data, optional_pad_length)
  def pad_data(data, nil) do
    data
  end
  def pad_data(data, pad_length) when pad_length < 256 do
    bit_pad_length = pad_length * 8
    <<pad_length, data::binary, 0::size(bit_pad_length)>>
  end

  def remove_padding(<<pad_length, rest::binary>>) do
    rest_length = :erlang.iolist_size(rest)
    data_length = rest_length - pad_length
    bit_pad_length = pad_length * 8
    <<data::binary-size(data_length), 0::size(bit_pad_length)>> = rest
    data
  end
end
