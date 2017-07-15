defmodule Ace.HTTP2.Frame.GoAway do
  @enforce_keys [:error, :last_stream_id, :debug]
  defstruct @enforce_keys

  def new(last_stream_id, error, debug \\ "") do
    %__MODULE__{last_stream_id: last_stream_id, error: error, debug: debug}
  end

  def serialize(frame) do
    payload = payload(frame)
    length = :erlang.iolist_size(payload)
    type = 7
    <<length::24, type::8, 0::8, 0::1, 0::31, payload::binary>>
  end

  # This func should take a struct
  def payload(%__MODULE__{last_stream_id: last_stream_id, error: error, debug: debug}) do
    <<0::1, last_stream_id::31, error_code(error)::32, debug::binary>>
  end

  def error_code(:no_error), do: 0x0
  def error_code(:protocol_error), do: 0x1
  def error_code(:internal_error), do: 0x2
  def error_code(:flow_control_error), do: 0x3
  def error_code(:settings_timeout), do: 0x4
  def error_code(:stream_closed), do: 0x5
  def error_code(:frame_size_error), do: 0x6
  def error_code(:refused_stream), do: 0x7
  def error_code(:cancel), do: 0x8
  def error_code(:compression_error), do: 0x9
  def error_code(:connect_error), do: 0xa
  def error_code(:enhance_your_calm), do: 0xb
  def error_code(:inadequate_security), do: 0xc
  def error_code(:http_1_1_required), do: 0xd
end
