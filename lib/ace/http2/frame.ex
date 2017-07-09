defmodule Ace.HTTP2.Frame do
  def read_next(<<header::bits-size(72), rest :: bits>>) do
    <<length::24, _::bits>> = header
    <<payload::binary-size(length), rest::bits>> = rest
    {header <> payload, rest}
  end
  def read_next(buffer) do
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
