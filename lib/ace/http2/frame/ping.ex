defmodule Ace.HTTP2.Frame.Ping do
  @enforce_keys [:identifier, :ack]
  defstruct @enforce_keys

  @type_id 6

  def new(identifier) when bit_size(identifier) == 64 do
    %__MODULE__{identifier: identifier, ack: false}
  end

  def ack(%__MODULE__{identifier: identifier, ack: false}) do
    %__MODULE__{identifier: identifier, ack: true}
  end

  def serialize(%__MODULE__{identifier: identifier, ack: ack}) do
    flags = if ack, do: <<1>>, else: <<0>>
    <<8::24, @type_id::8, flags::binary, 0::1, 0::31, identifier::binary>>
  end
end
