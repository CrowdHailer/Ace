defmodule Ace.HTTP2.Frame.Ping do
  @enforce_keys [:identifier, :ack]
  defstruct @enforce_keys

  @type_id 6

  # TODO informative error for bad ping identifier
  def new(identifier, ack \\ false) when bit_size(identifier) == 64 do
    %__MODULE__{identifier: identifier, ack: ack}
  end

  def ack(%__MODULE__{identifier: identifier, ack: false}) do
    new(identifier, true)
  end

  def decode({@type_id, flags, 0, identifier}) when bit_size(identifier) == 64 do
    ack = case flags do
      <<0>> ->
        false
      <<1>> ->
        true
    end

    {:ok, new(identifier, ack) |> IO.inspect}
  end
  def decode({@type_id, _flags, 0, _identifier}) do
    {:error, {:frame_size_error, "Ping identifier must be 64 bits"}}
  end

  def serialize(%__MODULE__{identifier: identifier, ack: ack}) do
    flags = if ack, do: <<1>>, else: <<0>>
    # DEBT should not need to calculate length
    length = :erlang.iolist_size(identifier)
    <<length::24, @type_id::8, flags::binary, 0::1, 0::31, identifier::binary>>
  end
end
