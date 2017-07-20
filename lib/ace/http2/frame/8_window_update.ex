defmodule Ace.HTTP2.Frame.WindowUpdate do
  @enforce_keys [:stream_id, :increment]
  defstruct @enforce_keys

  @max_increment (:math.pow(2, 31) - 1)

  def new(stream_id, increment) when increment < @max_increment do
    %__MODULE__{stream_id: stream_id, increment: increment}
  end

  def decode({8, <<0>>, stream_id, <<0::1, increment::31>>}) do
    {:ok, new(stream_id, increment)}
  end

  def serialize(%{stream_id: stream_id, increment: increment}) do
    <<4::24, 8::8, 0::8, 0::1, stream_id::31, 0::1, increment::31>>
  end
end
