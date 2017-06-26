defmodule Ace do
  def start_link(port, options) do
    IO.inspect(options)
    options = [
      mode: :binary,
      packet: :raw,
      active: false,
      reuseaddr: true,
      alpn_preferred_protocols: ["h2"]] ++ options
    {:ok, socket} = :ssl.listen(port, options)
    case :ssl.transport_accept(socket) do
      {:ok, socket} ->
        case :ssl.ssl_accept(socket) do
          :ok ->
            IO.inspect(:ssl.negotiated_protocol(socket))
            IO.inspect("boo")
            :timer.sleep(3_000)
            {:ok, {:tls, socket}}
          {:error, :closed} ->
            {:error, :econnaborted}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
end
