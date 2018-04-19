defmodule Ace.HTTP1.Endpoint do
  @moduledoc false

  require Logger

  @packet_timeout 10000

  alias Raxx.{Response, Data, Tail}
  alias Ace.HTTP1

  use GenServer

  @enforce_keys [
    :receive_state,
    :serializer_state,
    :socket,
    :worker,
    :monitor,
    :channel,
    :keep_alive
  ]

  defstruct @enforce_keys

  @impl GenServer
  def handle_info({t, s, packet}, state = %{socket: {t, s}}) do
    case HTTP1.Parser.parse(packet, state.receive_state) do
      {:ok, {parts, receive_state}} ->
        Enum.each(parts, fn part ->
          part = normalise_part(part, t)
          send(state.worker, {state.channel, part})
        end)

        :ok = Ace.Socket.set_active(state.socket)
        timeout = if HTTP1.Parser.done?(receive_state), do: :infinity, else: @packet_timeout
        {:noreply, %{state | receive_state: receive_state}, timeout}

      {:error, {:invalid_start_line, _line}} ->
        {:ok, {outbound, new_state}} = send_part(Raxx.response(:bad_request), state)
        Ace.Socket.send(state.socket, outbound)
        {:stop, :normal, state}

      {:error, {:invalid_header_line, _line}} ->
        {:ok, {outbound, new_state}} = send_part(Raxx.response(:bad_request), state)
        Ace.Socket.send(state.socket, outbound)
        {:stop, :normal, state}

      {:error, :start_line_too_long} ->
        {:ok, {outbound, new_state}} = send_part(Raxx.response(:uri_too_long), state)
        Ace.Socket.send(state.socket, outbound)
        {:stop, :normal, new_state}
    end
  end

  def handle_call({:send, channel, parts}, _from, state = %{channel: channel}) do
    {outbound, state} =
      Enum.reduce(parts, {"", state}, fn part, {buffer, state} ->
        {:ok, {outbound, next_state}} = send_part(part, state)
        {[buffer, outbound], next_state}
      end)

    Ace.Socket.send(state.socket, outbound)

    case state.serializer_state do
      %{next: :done} ->
        {:stop, :normal, {:ok, channel}, state}

      _ ->
        {:reply, {:ok, channel}, state}
    end
  end

  def handle_info(:timeout, state) do
    {:ok, {outbound, new_state}} = send_part(Raxx.response(:request_timeout), state)
    Ace.Socket.send(state.socket, outbound)
    {:stop, :normal, new_state}
  end

  def handle_info({transport, _socket}, state)
      when transport in [:tcp_closed, :ssl_closed] do
    {:stop, :normal, state}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, reason},
        state = %{worker: pid}
      ) do
    case state.serializer_state == Ace.HTTP1.Serializer.new() do
      true ->
        {:ok, {outbound, new_state}} = send_part(Raxx.response(:internal_server_error), state)
        Ace.Socket.send(state.socket, outbound)

      false ->
        # NOTE if any data already sent then canot send 500
        :ok
    end

    {:stop, :normal, new_state}
  end

  defp normalise_part(request = %{scheme: nil}, :tcp), do: %{request | scheme: :http}
  defp normalise_part(request = %{scheme: nil}, :ssl), do: %{request | scheme: :https}
  defp normalise_part(part, _transport), do: part

  defp send_part(response = %Response{}, state) do
    response =
      response
      |> Raxx.delete_header("connection")
      |> Raxx.set_header("connection", "close")

    {:ok, {outbound, serializer_state}} =
      Ace.HTTP1.Serializer.serialize(response, state.serializer_state)

    {:ok, {outbound, %{state | serializer_state: serializer_state}}}
  end

  defp send_part(part, state) do
    {:ok, {outbound, serializer_state}} =
      Ace.HTTP1.Serializer.serialize(part, state.serializer_state)

    {:ok, {outbound, %{state | serializer_state: serializer_state}}}
  end
end
