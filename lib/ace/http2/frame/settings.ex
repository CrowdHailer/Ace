defmodule Ace.HTTP2.Frame.Settings do
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
