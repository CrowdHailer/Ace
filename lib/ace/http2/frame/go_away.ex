defmodule Ace.HTTP2.Frame.GoAway do
  @enforce_keys [:error, :last_stream_id, :debug]
  defstruct @enforce_keys

  def frame do

  end

  # This func should take a struct
  def payload(last_stream_id, error, debug \\ "") do
    <<0::1, last_stream_id::31, error_code(error)::binary, debug::binary>>
  end

  def error_code(:protocol_error) do
    <<1::32>>
  end
end
