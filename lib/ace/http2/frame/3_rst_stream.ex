defmodule Ace.HTTP2.Frame.RstStream do
  @enforce_keys [:stream_id, :error]
  defstruct @enforce_keys

  def new(stream_id, error) do
    %__MODULE__{stream_id: stream_id, error: error}
  end

  def decode({3, _flags, stream_id, <<error_code::32>>}) do
    error = Ace.HTTP2.Frame.GoAway.error(error_code)
    {:ok, new(stream_id, error)}
  end

  def serialize(frame) do
    # TODO move to general errors
    payload = <<Ace.HTTP2.Frame.GoAway.error_code(frame.error)::32>>
    <<4::24, 3::8, 0::8, 0::1, frame.stream_id::31, payload::binary>>
  end
end
