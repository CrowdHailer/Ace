defmodule Ace.HTTP2.Settings do

  @enforce_keys [:max_frame_size]
  defstruct @enforce_keys

  @max_frame_size_default 16_384
  @max_frame_size_maximum 16_777_215

  def for_server(values \\ []) do
    # Difference for server is that push may never be true
    for_client(values)
  end

  def for_client(values \\ []) do
    max_frame_size = Keyword.get(values, :max_frame_size, @max_frame_size_default)
    case max_frame_size do
      value when value < @max_frame_size_default ->
        {:error, :max_frame_size_too_small}
      value when @max_frame_size_maximum < value ->
        {:error, :max_frame_size_too_large}
      value ->
        settings = %__MODULE__{
          max_frame_size: value
        }
        {:ok, settings}
    end
  end

  def update_frame(next, previous) do
    changed = if next.max_frame_size != previous.max_frame_size do
      [max_frame_size: next.max_frame_size]
    else
      []
    end
    Ace.HTTP2.Frame.Settings.new(changed)
  end

  def apply_frame(frame, current) do
    if new_value = frame.max_frame_size do
      Map.put(current, :max_frame_size, new_value)
    else
      current
    end
  end
end
