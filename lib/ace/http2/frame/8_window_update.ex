defmodule Ace.HTTP2.Frame.WindowUpdate do
  @enforce_keys [:stream_id, :increment]
  defstruct @enforce_keys

  @max_increment (:math.pow(2, 31) - 1)

  def new(stream_id, increment) when increment < @max_increment do
    %__MODULE__{stream_id: stream_id, increment: increment}
  end

  def decode({8, _flags, stream_id, <<0::1, increment::31>>}) when 0 < increment and increment < @max_increment do
    {:ok, new(stream_id, increment)}
  end
  def decode({8, _flags, _stream_id, <<0::1, increment::31>>}) when increment > @max_increment do
    {:error, {:flow_control_error, "window update too large"}}
  end
  def decode({8, _flags, _stream_id, <<0::1, 0::31>>}) do
    # DEBT this is a stream level error
    {:error, {:protocol_error, "window update cannot be of size 0"}}
  end
  def decode({8, _flags, _stream_id, _payload}) do
    {:error, {:frame_size_error, "window update frame payload must be 4 octets"}}
  end

  def serialize(%{stream_id: stream_id, increment: increment}) do
    <<4::24, 8::8, 0::8, 0::1, stream_id::31, 0::1, increment::31>>
  end
end
