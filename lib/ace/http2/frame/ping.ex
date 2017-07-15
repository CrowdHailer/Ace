defmodule Ace.HTTP2.Frame.Ping do
  @enforce_keys [:identifier, :ack]
  defstruct @enforce_keys

  @type_id 6

  # TODO informative error for bad ping identifier
  def new(identifier) when bit_size(identifier) == 64 do
    %__MODULE__{identifier: identifier, ack: false}
  end

  def ack(%__MODULE__{identifier: identifier, ack: false}) do
    %__MODULE__{identifier: identifier, ack: true}
  end

  def serialize(%__MODULE__{identifier: identifier, ack: ack}) do
    flags = if ack, do: <<1>>, else: <<0>>
    # DEBT should not need to calculate length
    length = :erlang.iolist_size(identifier)
    <<length::24, @type_id::8, flags::binary, 0::1, 0::31, identifier::binary>>
  end
end
