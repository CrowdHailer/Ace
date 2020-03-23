defmodule Ace.HTTP2.Frame.GoAway do
  @moduledoc false

  @type t :: %__MODULE__{
          error: Ace.HTTP2.Errors.error(),
          last_stream_id: Ace.HTTP2.Frame.stream_id(),
          debug: binary
        }

  alias Ace.HTTP2.{Errors}

  @enforce_keys [:error, :last_stream_id, :debug]
  defstruct @enforce_keys

  @spec new(Ace.HTTP2.Frame.stream_id(), Ace.HTTP2.Errors.error(), binary) :: t()
  def new(last_stream_id, error, debug \\ <<>>) do
    %__MODULE__{last_stream_id: last_stream_id, error: error, debug: debug}
  end

  @spec decode({7, any, 0, binary}) :: {:ok, t()}
  def decode({7, _flags, 0, <<0::1, last_stream_id::31, error_code::32, debug::binary>>}) do
    error = Errors.decode(error_code)
    {:ok, new(last_stream_id, error, debug)}
  end

  @spec serialize(t()) :: binary
  def serialize(frame) do
    payload = payload(frame)
    length = byte_size(payload)
    type = 7
    <<length::24, type::8, 0::8, 0::1, 0::31, payload::binary>>
  end

  defp payload(%__MODULE__{last_stream_id: last_stream_id, error: error, debug: debug}) do
    <<0::1, last_stream_id::31, Errors.encode(error)::32, debug::binary>>
  end
end

defimpl Inspect, for: Ace.HTTP2.Frame.GoAway do
  def inspect(
        %Ace.HTTP2.Frame.GoAway{error: error, debug: debug, last_stream_id: last_stream_id},
        _opts
      ) do
    # RFC7540 Debug information could contain security or privacy-sensitive data.
    # Logged or otherwise persistently stored debug data MUST have adequate safeguards to
    # prevent unauthorized access.
    "GO_AWAY(error: #{error}, debug: <REDACTED>, last_stream_id: #{last_stream_id})"
  end
end
