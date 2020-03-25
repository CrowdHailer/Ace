defmodule Ace.HTTP2.Frame.Priority do
  @moduledoc false

  alias Ace.HTTP2.Frame

  @type t :: %__MODULE__{
          stream_id: Frame.stream_id(),
          stream_dependency: Frame.stream_id(),
          weight: Frame.weight(),
          exclusive: boolean
        }

  @enforce_keys [:stream_id, :stream_dependency, :weight, :exclusive]
  defstruct @enforce_keys

  @spec new(
          Frame.stream_id(),
          Frame.stream_id(),
          Frame.weight(),
          boolean
        ) :: t()
  def new(stream_id, stream_dependency, weight, exclusive) do
    %__MODULE__{
      stream_id: stream_id,
      stream_dependency: stream_dependency,
      weight: weight,
      exclusive: exclusive
    }
  end

  @spec decode({2, any(), Frame.stream_id(), binary()}) ::
          {:ok, t()} | {:error, {:protocol_error, String.t()}}
  def decode({2, _flags, stream_id, <<exclusive::1, stream_dependency::31, weight::8>>})
      when stream_id > 0 do
    exclusive = exclusive == 1

    if stream_id == stream_dependency do
      {:error, {:protocol_error, "Priority frame can not be dependent on own stream"}}
    else
      {:ok, new(stream_id, stream_dependency, weight, exclusive)}
    end
  end

  def decode({2, _flags, 0, <<_::40>>}) do
    {:error, {:protocol_error, "Priority frame not valid on stream 0"}}
  end

  def decode({2, _flags, _stream_id, _payload}) do
    {:error, {:protocol_error, "Priority frame invalid payload length"}}
  end

  @spec serialize(t()) :: binary
  def serialize(frame) do
    exclusive = if frame.exclusive, do: 1, else: 0

    <<
      5::24,
      2::8,
      0::8,
      0::1,
      frame.stream_id::31,
      exclusive::1,
      frame.stream_dependency::31,
      frame.weight::8
    >>
  end

  defimpl Inspect, for: Frame.Priority do
    def inspect(
          %{
            stream_id: stream_id,
            stream_dependency: stream_dependency,
            weight: weight,
            exclusive: exclusive
          },
          _opts
        ) do
      "PRIORITY(stream_id: #{stream_id}, stream_dependency: #{stream_dependency}, weight: #{
        weight
      }, exclusive: #{exclusive})"
    end
  end
end
