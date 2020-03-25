defmodule Ace.HTTP2.Settings do
  @moduledoc false

  @type window_size :: 0..2_147_483_647
  @type max_frame_size :: 16_384..16_777_215
  @type max_concurrent_streams :: 0..2_147_483_647

  @type t :: %__MODULE__{
          enable_push: boolean,
          max_concurrent_streams: max_concurrent_streams(),
          max_frame_size: max_frame_size(),
          initial_window_size: window_size()
        }
  @enforce_keys [
    :enable_push,
    :max_concurrent_streams,
    :initial_window_size,
    :max_frame_size
  ]
  defstruct @enforce_keys

  @max_frame_size_default 16384
  @max_frame_size_maximum 16_777_215

  @initial_window_size_default 65535
  @initial_window_size_minimum 0
  @initial_window_size_maximum 2_147_483_647

  @type setting ::
          {:max_frame_size, max_frame_size}
          | {:max_concurrent_streams, max_concurrent_streams()}
          | {:initial_window_size, window_size()}
          | {:enable_push, boolean}

  @type settings :: [setting()]

  @spec for_server(settings()) ::
          {:ok, t()}
          | {:error,
             :max_frame_size_too_small
             | :max_frame_size_too_large
             | :initial_window_size_too_small
             | :initial_window_size_too_large}
  def for_server(values \\ []) do
    for_client([{:enable_push, false} | values])
  end

  @spec for_client(settings()) ::
          {:ok, t()}
          | {:error,
             :max_frame_size_too_small
             | :max_frame_size_too_large
             | :initial_window_size_too_small
             | :initial_window_size_too_large}
  def for_client(values \\ []) do
    case Keyword.get(values, :max_frame_size, @max_frame_size_default) do
      value when value < @max_frame_size_default ->
        {:error, :max_frame_size_too_small}

      value when @max_frame_size_maximum < value ->
        {:error, :max_frame_size_too_large}

      max_frame_size ->
        case Keyword.get(values, :initial_window_size, @initial_window_size_default) do
          value when value < @initial_window_size_minimum ->
            {:error, :initial_window_size_too_small}

          value when @initial_window_size_maximum < value ->
            {:error, :initial_window_size_too_large}

          initial_window_size ->
            # DEBT replace max to be unlimited
            max_concurrent_streams = Keyword.get(values, :max_concurrent_streams, 10000)
            enable_push = Keyword.get(values, :enable_push, true)

            settings = %__MODULE__{
              max_frame_size: max_frame_size,
              max_concurrent_streams: max_concurrent_streams,
              initial_window_size: initial_window_size,
              enable_push: enable_push
            }

            {:ok, settings}
        end
    end
  end

  @spec update_frame(t(), t()) :: Ace.HTTP2.Frame.Settings.t()
  def update_frame(next, previous) do
    changed =
      if next.max_frame_size != previous.max_frame_size do
        [max_frame_size: next.max_frame_size]
      else
        []
      end

    changed =
      if next.initial_window_size != previous.initial_window_size do
        [initial_window_size: next.initial_window_size]
      else
        []
      end ++ changed

    changed =
      if next.enable_push != previous.enable_push do
        [enable_push: next.enable_push]
      else
        []
      end ++ changed

    changed =
      if next.max_concurrent_streams != previous.max_concurrent_streams do
        [max_concurrent_streams: next.max_concurrent_streams]
      else
        []
      end ++ changed

    Ace.HTTP2.Frame.Settings.new(changed)
  end

  @spec apply_frame(Ace.HTTP2.Frame.Settings.t(), Ace.HTTP2.Settings.t()) ::
          Ace.HTTP2.Settings.t()
  def apply_frame(frame, settings) do
    Enum.reduce(@enforce_keys, settings, fn key, settings ->
      case Map.get(frame, key) do
        nil ->
          settings

        new_value ->
          Map.put(settings, key, new_value)
      end
    end)
  end
end
