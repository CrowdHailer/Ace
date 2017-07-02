defmodule Ace.HTTP2.Frame do
  def read_next(<<header::bits-size(72), rest :: bits>>) do
    <<length::24, _::bits>> = header
    <<payload::binary-size(length), rest::bits>> = rest
    {header <> payload, rest}
  end
  def read_next(buffer) do
    {nil, buffer}
  end
  defmodule Data do
    defstruct [data: "", padding: 0, end: false]
    def parse_flags(<<_::5, padded_flag::1, _::1, end_stream_flag::1>>) do
      %{
        padded: padded_flag == 1,
        end_stream_flag: end_stream_flag == 1,
      }
    end

    # @type <<4>>
    # @reserved <<0::1>>

    # def parse(<<
    #   length::24,
    #   @type,
    #   flags(),
    #   @reserved,
    #   stream_id(id), b::8, p::binary-size(length - b - 1), padding::binary-size(p)>>) do
    #
    # end
    #
    # def parse(<<length::24>> <> rest, nil) do
    #   parse(rest, {length})
    # end
    # def parse(@type <> rest, state) do
    #
    # end


  end
  # <<length::24, Data.type(), Data.flags(:padded, end_stream_flag), 0::1, id:31>>
  defmodule WindowUpdate do
    defmacro type do
      <<8>>
    end
  end
end
