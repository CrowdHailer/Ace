defmodule Ace.HTTP2.Frame.Priority do
  @enforce_keys [:stream_id, :stream_dependency, :weight, :exclusive]
  defstruct @enforce_keys

  def new(stream_id, stream_dependency, weight, exclusive) do
    %__MODULE__{
      stream_id: stream_id,
      stream_dependency: stream_dependency,
      weight: weight,
      exclusive: exclusive
    }
  end

  def decode({2, _flags, stream_id, <<exclusive::1, stream_dependency::31, weight::8>>}) do
    exclusive = exclusive == 1
    {:ok, new(stream_id, stream_dependency, weight, exclusive)}
  end

  def serialize(frame) do
    exclusive = if frame.exclusive, do: 1, else: 0
    <<5::24, 2::8, 0::8, 0::1, frame.stream_id::31, exclusive::1, frame.stream_dependency::31, frame.weight::8>>
  end
end
