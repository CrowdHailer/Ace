defmodule Ace.HTTP2.Frame.GoAway do
  @moduledoc false

  alias Ace.HTTP2.{
    Errors
  }

  @enforce_keys [:error, :last_stream_id, :debug]
  defstruct @enforce_keys

  def new(last_stream_id, error, debug \\ "") do
    %__MODULE__{last_stream_id: last_stream_id, error: error, debug: debug}
  end

  def decode({7, _flags, 0, <<0::1, last_stream_id::31, error_code::32, debug::binary>>}) do
    error = Errors.decode(error_code)
    {:ok, new(last_stream_id, error, debug)}
  end

  def serialize(frame) do
    payload = payload(frame)
    length = :erlang.iolist_size(payload)
    type = 7
    <<length::24, type::8, 0::8, 0::1, 0::31, payload::binary>>
  end

  def payload(%__MODULE__{last_stream_id: last_stream_id, error: error, debug: debug}) do
    <<0::1, last_stream_id::31, Errors.encode(error)::32, debug::binary>>
  end

  defimpl Inspect, for: Ace.HTTP2.Frame.GoAway do
    def inspect(%{stream_id: stream_id, error: error, debug: debug, last_stream_id: last_stream_id}, _opts) do
      "GO_AWAY(stream_id: #{stream_id}, error: #{error}, debug: #{debug}, last_stream_id: #{last_stream_id})"
    end
  end
end
