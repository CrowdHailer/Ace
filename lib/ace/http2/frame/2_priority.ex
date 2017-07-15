defmodule Ace.HTTP2.Frame.Priority do
  @enforce_keys [:stream_id, :stream_dependency, :weight]
  defstruct @enforce_keys

  def new(stream_id, stream_dependency, weight) do
    %__MODULE__{stream_id: stream_id, stream_dependency: stream_dependency, weight: weight}
  end

  def decode({2, <<0>>, stream_id, <<0::1, stream_dependency::31, weight::8>>}) do
    {:ok, %__MODULE__{stream_id: stream_id, stream_dependency: stream_dependency, weight: weight}}
  end

  def serialize(frame) do
    <<5::24, 2::8, 0::8, 0::1, frame.stream_id::31, 0::1, frame.stream_dependency::31, frame.weight::8>>
  end
end
