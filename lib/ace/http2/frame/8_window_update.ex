defmodule Ace.HTTP2.Frame.WindowUpdate do
  @enforce_keys [:stream_id, :increment]
  defstruct @enforce_keys

  def decode({8, <<0>>, stream_id, <<0::1, increment::31>>}) do
    {:ok, %__MODULE__{stream_id: stream_id, increment: increment}}
  end

  def serialize(_) do
    raise "TODO implement"
  end
end
