defmodule Support do
  def read_next(connection, timeout \\ :infinity) do
    case :ssl.recv(connection, 9, timeout) do
      {:ok, <<length::24, type::8, flags::binary-size(1), 0::1, stream_id::31>>} ->
        case length do
          0 ->
            {:ok, {type, flags, stream_id, ""}}
          length ->
            {:ok, payload} = :ssl.recv(connection, length, timeout)
            Ace.HTTP2.Frame.decode({type, flags, stream_id, payload})
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
end
