defmodule Ace.HTTP2.Frame do
  def read_next(<<header::bits-size(72), rest :: bits>>) do
    <<length::24, _::bits>> = header
    <<payload::binary-size(length), rest::bits>> = rest
    {header <> payload, rest}
  end
  def read_next(buffer) do
    {nil, buffer}
  end
end
