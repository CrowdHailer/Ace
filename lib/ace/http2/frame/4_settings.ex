defmodule Ace.HTTP2.Frame.Settings do
  defstruct [:ack]

  def decode({4, flags, stream_id, payload}) do
    {:ok, %__MODULE__{ack: false}}
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
