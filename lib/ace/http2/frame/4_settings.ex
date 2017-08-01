defmodule Ace.HTTP2.Frame.Settings do
  @enforce_keys [:ack]
  @parameter_keys [
    :header_table_size,
    :enable_push,
    :max_concurrent_streams,
    :initial_window_size,
    :max_frame_size,
    :max_header_list_size
  ]
  defstruct @enforce_keys ++ @parameter_keys

  def new(parameters \\ []) do
    parameters = Enum.into(parameters, %{})
    %__MODULE__{ack: false} |> Map.merge(parameters)
  end

  def ack() do
    %__MODULE__{ack: true}
  end

  def decode({4, <<_::7, 0::1>>, 0, payload}) do
    case parse_settings(payload) do
      {:ok, settings} ->
        {:ok, new(settings)}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def decode({4, <<_::7, 1::1>>, 0, ""}) do
    {:ok, %__MODULE__{ack: true}}
  end

  def serialize(frame = %{ack: false}) do
    type = 4
    flags = 0
    stream_id = 0
    payload = Enum.reduce(@parameter_keys, [], fn(key, acc) ->
      case Map.get(frame, key) do
        nil ->
          acc
        value ->
          [setting_parameter(key, value) | acc]
      end
    end)
    |> Enum.reverse()
    |> :erlang.iolist_to_binary
    length = :erlang.iolist_size(payload)
    <<length::24, type::8, flags::8, 0::1, stream_id::31, payload::binary>>
  end
  def serialize(%{ack: true}) do
    type = 4
    <<0::24, type::8, 1::8, 0::1, 0::31>>
  end

  def parse_settings(binary, settings \\ %{})
  def parse_settings(<<>>, settings) do
    {:ok, settings}
  end
  def parse_settings(<<identifier::16, value::32, rest::binary>>, settings) do
    case cast_setting(identifier, value) do
      {:ok, {:unknown_setting, _value}} ->
        {:ok, settings}
      {:ok, {setting, value}} ->
        settings = Map.put(settings, setting, value)
        parse_settings(rest, settings)
      {:error, reason} ->
        {:error, reason}
    end
  end
  def cast_setting(1, value) do
    {:ok, {:header_table_size, value}}
  end
  def cast_setting(2, 0) do
    {:ok, {:enable_push, false}}
  end
  def cast_setting(2, 1) do
    {:ok, {:enable_push, true}}
  end
  def cast_setting(2, _) do
    {:error, {:protocol_error, "invalid value for enable_push setting"}}
  end
  def cast_setting(3, value) do
    {:ok, {:max_concurrent_streams, value}}
  end
  # DEBT is minumum 0 or 1
  def cast_setting(4, value) when 0 <= value and value <= 2_147_483_647 do
    {:ok, {:initial_window_size, value}}
  end
  def cast_setting(4, _value) do
    {:error, {:protocol_error, "invalid value for initial_window_size setting"}}
  end
  def cast_setting(5, value) when 16_384 <= value and value <= 16_777_215 do
    {:ok, {:max_frame_size, value}}
  end
  def cast_setting(5, _value) do
    {:error, {:protocol_error, "invalid value for max_frame_size setting"}}
  end
  def cast_setting(6, value) do
    {:ok, {:max_header_list_size, value}}
  end
  def cast_setting(identifier, value) when identifier > 6 do
    {:ok, {:unknown_setting, value}}
  end

  def setting_parameter(:header_table_size, value) do
    <<1::16, value::32>>
  end
  def setting_parameter(:initial_window_size, value) do
    <<4::16, value::32>>
  end
  def setting_parameter(:max_frame_size, value) do
    <<5::16, value::32>>
  end

  def parameters_to_payload(parameters, payload \\ [])
  def parameters_to_payload([], payload) do
    Enum.reverse(payload)
    |> :erlang.iolist_to_binary
  end
  def parameters_to_payload([{:header_table_size, value} | rest], payload) do
    payload = [<<1::16, value::32>> | payload]
    parameters_to_payload(rest, payload)
  end
  def parameters_to_payload([{:max_frame_size, value} | rest], payload) do
    payload = [<<5::16, value::32>> | payload]
    parameters_to_payload(rest, payload)
  end
end
