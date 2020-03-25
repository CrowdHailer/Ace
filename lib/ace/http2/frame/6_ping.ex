defmodule Ace.HTTP2.Frame.Ping do
  @moduledoc false

  @type t :: %__MODULE__{identifier: binary, ack: boolean}

  @enforce_keys [:identifier, :ack]
  defstruct @enforce_keys

  @type_id 6

  @spec new(binary, boolean) :: t()
  def new(identifier, ack \\ false) when bit_size(identifier) == 64 do
    %__MODULE__{identifier: identifier, ack: ack}
  end

  @spec ack(%__MODULE__{identifier: binary, ack: false}) :: t()
  def ack(%__MODULE__{identifier: identifier, ack: false}) do
    new(identifier, true)
  end

  @spec decode({6, binary, Ace.HTTP2.Frame.stream_id(), binary}) ::
          {:ok, t()} | {:error, {:frame_size_error, string}} | {:error, {:protocol_error, string}}
  def decode({@type_id, <<_::7, ack_flag::1>>, 0, identifier}) when bit_size(identifier) == 64 do
    ack =
      case ack_flag do
        0 ->
          false

        1 ->
          true
      end

    {:ok, new(identifier, ack)}
  end

  def decode({@type_id, _flags, 0, _identifier}) do
    {:error, {:frame_size_error, "Ping identifier must be 64 bits"}}
  end

  def decode({@type_id, _flags, _stream_id, _identifier}) do
    {:error, {:protocol_error, "Ping must be for stream 0"}}
  end

  @spec serialize(t()) :: binary
  def serialize(%__MODULE__{identifier: identifier, ack: ack}) do
    flags = if ack, do: <<1>>, else: <<0>>
    # DEBT should not need to calculate length
    length = byte_size(identifier)
    <<length::24, @type_id::8, flags::binary, 0::1, 0::31, identifier::binary>>
  end

  defimpl Inspect, for: Ace.HTTP2.Frame.Ping do
    def inspect(%{ack: ack, identifier: identifier}, _opts) do
      "PING(ack: #{ack}, identifier: #{inspect(identifier)})"
    end
  end
end
