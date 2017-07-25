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
    {:ok, settings} = parse_settings(payload)
    {:ok, new(settings)}
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

  def parse_settings(binary, data \\ %{})
  # <<identifier::16, value::32, rest::bitstring>> = bin
  # setting_parameter(identifier, value)
  def parse_settings(<<>>, data) do
    {:ok, data}
  end
  def parse_settings(<<1::16, value::32, rest::binary>>, data) do
    data = Map.put(data, :header_table_size, value)
    parse_settings(rest, data)
  end
  def parse_settings(<<4::16, value::32, rest::binary>>, data) do
    data = Map.put(data, :initial_window_size, value)
    parse_settings(rest, data)
  end
  def parse_settings(<<5::16, value::32, rest::binary>>, data) do
    data = Map.put(data, :max_frame_size, value)
    parse_settings(rest, data)
  end
  def parse_settings(<<_::16, _value::32, rest::binary>>, data) do
    IO.inspect("TODO more settings")
    parse_settings(rest, data)
  end

  def setting_parameter(:header_table_size, value) do
    <<1::16, value::32>>
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
