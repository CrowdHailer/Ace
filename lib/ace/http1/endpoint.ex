defmodule Ace.HTTP1.Endpoint do
  @moduledoc false

  require Logger

  @max_pending_request_part_count 4
  @packet_timeout 10000

  alias Raxx.{Response, Data, Tail}
  alias Ace.HTTP1

  use GenServer

  @enforce_keys [
    :status,
    :receive_state,
    :socket,
    :worker,
    :monitor,
    :channel,
    :keep_alive,
    :pending_ack_count
  ]

  defstruct @enforce_keys

  @impl GenServer
  def init(args) do
    {:ok, args}
  end

  @impl GenServer
  def handle_call({:send, channel, parts}, from, state = %{channel: channel}) do
    {outbound, state} =
      Enum.reduce(parts, {"", state}, fn part, {buffer, state} ->
        {:ok, {outbound, next_state}} = send_part(part, state)
        {[buffer, outbound], next_state}
      end)

    Ace.Socket.send(state.socket, outbound)

    case state.status do
      {_, :complete} ->
        GenServer.reply(from, {:ok, channel})
        {:stop, :normal, state}

      {_, _incomplete} ->
        {:reply, {:ok, channel}, state}
    end
  end

  @impl GenServer
  def handle_info({t, s, packet}, state = %{socket: {t, s}}) do
    case HTTP1.Parser.parse(packet, state.receive_state) do
      {:ok, {parts, receive_state}} ->
        Enum.each(parts, fn part ->
          part = normalise_part(part, t)
          send(state.worker, {state.channel, part})
        end)

        pending_ack_count = state.pending_ack_count + Enum.count(parts)

        timeout =
          if pending_ack_count < @max_pending_request_part_count do
            :ok = Ace.Socket.set_active(state.socket)
            if HTTP1.Parser.done?(receive_state), do: :infinity, else: @packet_timeout
          else
            :infinity
          end

        {:noreply, %{state | receive_state: receive_state, pending_ack_count: pending_ack_count},
         timeout}

      {:error, reason} ->
        {:ok, {outbound, new_state}} = send_part(Raxx.error_response(reason), state)

        Ace.Socket.send(new_state.socket, outbound)
        {:stop, :normal, new_state}
    end
  end

  def handle_info(:ack, state = %{receive_state: receive_state}) do
    pending_ack_count = state.pending_ack_count - 1

    timeout =
      if pending_ack_count == @max_pending_request_part_count - 1 do
        # setting active only for @max_pending_request_part_count - 1 to make sure the socket doesn't
        # get set to active multiple times before receiving the next packet
        :ok = Ace.Socket.set_active(state.socket)
        if HTTP1.Parser.done?(receive_state), do: :infinity, else: @packet_timeout
      else
        :infinity
      end

    {:noreply, %{state | pending_ack_count: pending_ack_count}, timeout}
  end

  def handle_info(:timeout, state) do
    {:ok, {outbound, new_state}} = send_part(Raxx.error_response(:request_timeout), state)

    Ace.Socket.send(state.socket, outbound)
    {:stop, :normal, new_state}
  end

  def handle_info({transport, _socket}, state)
      when transport in [:tcp_closed, :ssl_closed] do
    {:stop, :normal, state}
  end

  # NOTE if any data already sent then canot send 500
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        state = %{worker: pid, status: {_, :response}}
      ) do
    {:ok, {outbound, new_state}} = send_part(Raxx.error_response(:internal_server_error), state)

    Ace.Socket.send(state.socket, outbound)
    {:stop, :normal, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state = %{worker: pid}) do
    {:stop, reason, state}
  end

  defp normalise_part(request = %{scheme: nil}, :tcp), do: %{request | scheme: :http}
  defp normalise_part(request = %{scheme: nil}, :ssl), do: %{request | scheme: :https}
  defp normalise_part(part, _transport), do: part

  defp send_part(response = %Response{}, state = %{status: {up, :response}}) do
    case Raxx.HTTP1.serialize_response(response, connection: :close) do
      {head, :chunked} ->
        new_status = {up, :chunked_body}
        new_state = %{state | status: new_status}

        {:ok, {head, new_state}}

      {head, {:bytes, content_length}} ->
        new_status = {up, {:body, content_length}}
        new_state = %{state | status: new_status}

        {:ok, {head, new_state}}

      {head, {:complete, body}} ->
        new_status = {up, :complete}
        new_state = %{state | status: new_status}

        {:ok, {[head, body], new_state}}
    end
  end

  defp send_part(data = %Data{}, state = %{status: {up, {:body, remaining}}}) do
    remaining = remaining - :erlang.iolist_size(data.data)
    new_status = {up, {:body, remaining}}
    new_state = %{state | status: new_status}
    {:ok, {[data.data], new_state}}
  end

  defp send_part(%Tail{headers: []}, state = %{status: {up, {:body, 0}}}) do
    new_status = {up, :complete}
    new_state = %{state | status: new_status}
    {:ok, {[], new_state}}
  end

  defp send_part(%Data{data: data}, state = %{status: {_up, :chunked_body}}) do
    chunk = Raxx.HTTP1.serialize_chunk(data)
    {:ok, {[chunk], state}}
  end

  defp send_part(%Tail{headers: []}, state = %{status: {up, :chunked_body}}) do
    chunk = Raxx.HTTP1.serialize_chunk("")
    new_status = {up, :complete}
    new_state = %{state | status: new_status}

    {:ok, {[chunk], new_state}}
  end
end
