defmodule Ace.Frame do
  length = quote do: length
  frame_match = quote do: <<unquote(length)::24, _::48, _::binary-size(unquote(length))>>

  def pop(<<unquote(frame_match), rest::binary>>) do
    IO.inspect(unquote(length))
    IO.inspect(rest)
    # <<frame::binary-size(l + 9), rest::bits>> = binary
    # {frame, rest}
  end
  def parse do

  end
  # def read_next(<<header::bits-size(72), rest :: bits>>) do
  #   <<length::24, _::bits>> = header
  #   <<payload::binary-size(length), _::bits>> = rest
  # end
  defmodule Data do
    defstruct [data: "", padding: 0, end: false]
    def parse_flags(<<_::5, padded_flag::1, _::1, end_stream_flag::1>>) do
      %{
        padded: padded_flag == 1,
        end_stream_flag: end_stream_flag == 1,
      }
    end

    @type <<4>>
    @reserved <<0::1>>

    def parse(<<
      length::24,
      @type,
      flags(),
      @reserved,
      stream_id(id), b::8, p::binary-size(length - b - 1), padding::binary-size(p)>>) do

    end

    def parse(<<length::24>> <> rest, nil) do
      parse(rest, {length})
    end
    def parse(@type <> rest, state) do

    end


  end
  # <<length::24, Data.type(), Data.flags(:padded, end_stream_flag), 0::1, id:31>>
  defmodule WindowUpdate do
    defmacro type do
      <<8>>
    end
  end
end
defmodule Ace.FrameTest do

  use ExUnit.Case

  test "matching" do
    Ace.Frame.pop(<<0 :: 24, 4 :: 8, 0 :: 8, 0 :: 1, 0 :: 31>> <> "other")
    |> IO.inspect
  end

  @priority <<2>>
  @settings <<4>>
  @window_update <<8>>

  def parse_flags(<<0>>) do
    %{ack: false}
  end
  def parse_flags(<<1>>) do
    %{ack: true}
  end

  def parse_frame(<<@priority, flags :: bits - size(8), 0 :: 1, stream_id :: 31>>, payload) do
    flags = parse_priority(flags, payload)
    {:settings, flags}
  end
  def parse_frame(<<@settings, flags :: bits - size(8), 0 :: 1, 0 :: 31>>, payload) do
    flags = parse_settings(flags, payload)
    {:settings, flags}
  end
  def parse_frame(<<@window_update, flags :: bits - size(8), 0 :: 1, 0 :: 31>>, payload) do
    flags = parse_window_update(flags, payload)
    {:settings, flags}
  end

  def parse_priority(<<0>>, <<0::1, stream_dependency::31, weight::8>>) do
    IO.inspect(stream_dependency)
  end

  def parse_settings(<<1>>, "") do
    :ack
  end
  def parse_settings(<<0>>, payload) do
    parse_parameters(payload)
  end

  def parse_parameters(binary, parameters \\ %{})
  def parse_parameters(<<>>, parameters) do
    parameters
  end
  def parse_parameters(<<1 :: 16, value :: 32, rest :: binary>>, parameters) do
    IO.inspect(value)
    parse_parameters(rest)
  end
  def parse_parameters(<<4 :: 16, value :: 32, rest :: binary>>, parameters) do
    IO.inspect(value)
    parse_parameters(rest)
  end
  def parse_parameters(<<5 :: 16, value :: 32, rest :: binary>>, parameters) do
    IO.inspect(value)
    parse_parameters(rest)
  end

  def parse_window_update(<<0>>, <<0 :: 1, window_size_increment :: 31>>) do
    IO.inspect(window_size_increment)
  end

  def read_frame(<<length :: 24, head :: binary - size(6), rest :: bits>>) do
    <<payload :: binary - size(length), rest :: bits>> = rest
    {{head, payload}, rest}
  end

@tag :skip
  test "" do
    read_frame(<<0 :: 24, 4 :: 8, 0 :: 8, 0 :: 1, 0 :: 31>>)
    |> IO.inspect
  end

@tag :skip
  test "firefox 1" do
    {{head, payload}, ""} = read_frame(<<0, 0, 18, 4, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 4, 0, 2, 0, 0, 0, 5, 0, 0,
  64, 0>>)
    parse_frame(head, payload)
  end
  @tag :skip
  test "firefox 2" do
    {{head, payload}, ""} = read_frame(<<0, 0, 4, 8, 0, 0, 0, 0, 0, 0, 191, 0, 1>>)
    parse_frame(head, payload)
  end
  @tag :skip
  test "firefox 3" do
    {{head, payload}, ""} = read_frame(<<0, 0, 5, 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 200>>)
    parse_frame(head, payload)
  end
  @tag :skip
  test "firefox 4" do
    <<0, 0, 5, 2, 0, 0, 0, 0, 5, 0, 0, 0, 0, 100>>
  end
  @tag :skip
  test "firefox 5" do
    <<0, 0, 5, 2, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0>>
  end
  @tag :skip
  test "firefox 6" do
    <<0, 0, 5, 2, 0, 0, 0, 0, 9, 0, 0, 0, 7, 0>>
  end
  @tag :skip
  test "firefox 7" do
    <<0, 0, 5, 2, 0, 0, 0, 0, 11, 0, 0, 0, 3, 0>>
  end
end
