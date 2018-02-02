defmodule Ace.HTTP2.Endpoint do
  @moduledoc """
  """

  use GenServer

  @enforce_keys [
    :socket,
    :unprocessed,
    :read_status,
    :streams,
    :worker_supervisor,
    :next_remote_stream_id,
    :decode_context
  ]

  defstruct @enforce_keys

  def server(socket, worker_supervisor) do
    %__MODULE__{
      socket: socket,
      unprocessed: "",
      read_status: :client_preface,
      streams: %{},
      worker_supervisor: worker_supervisor,
      next_remote_stream_id: 1,
      decode_context: Ace.HPack.new_context(4096)
    }
  end

  @impl GenServer
  def handle_info({transport, socket, packet}, state = %__MODULE__{socket: {transport, socket}})
      when transport in [:tcp, :ssl] do
    case receive_packet(state, packet) do
      {:ok, {outbound, new_state}} ->
        :ok = send_all(outbound)
        {:noreply, new_state}

      {:error, reason} ->
        :ok = send_all([state.socket, Frame.GoAway])
        {:stop, :normal, state}
    end
  end

  def handle_info({closed, socket}, state = %{socket: {_, socket}})
      when closed in [:tcp_closed, :ssl_closed] do
    # Kill all streams
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    worker_exited(state, ref, reason)
  end

  def handle_call({:send, pid, stuff}, from, state) do
    # make stream
  end

  def handle_call({:send, channel, stuff}, from, state) do
    # lookup stream
  end

  def handle_call({:ping, identifier}, from, state) do
    # case
    # state, identifier, from) do
    #   {:ok, {outbound, new_state}} ->
    #     continue(new_state, outbound)
    # end
  end

  def handle_call({:reset, channel, reason}, from, state) do
  end

  def handle_call({:stop, reason}, from, state) do
  end

  defp continue(new_state, outbound) do
    :ok = send_all(outbound)
    {:noreply, new_state}
  end

  defp stop(state, reason) do
    :ok = send_all([state.socket, Frame.GoAway])
    {:stop, :normal, state}
  end

  defp send_all(_) do
    # This should have all the logging
  end

  alias Ace.HTTP2.Frame

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  # Implicit process upstreamed bits
  # `receive_packet`
  # In system read/write from channel/link/pipe
  # Could not bother having handshake as a state
  # @spec receive_packet(binary(), endpoint) :: {:ok, {actions, endpoint}} | :connection_error
  # TODO rename -> max_frame_size
  def receive_packet(endpoint, packet)

  # unprocessed -> unparsed
  # Frame.pop -> Frame.parse
  def receive_packet(state = %__MODULE__{read_status: :client_preface}, packet) do
    case state.unprocessed <> packet do
      @preface <> unprocessed ->
        case Frame.parse(unprocessed, max_length: 16384) do
          {:ok, {%Frame.Settings{ack: false}, unprocessed}} ->
            new_state = %{state | read_status: :normal}
            # rename process_frame
            case receive_packet(new_state, unprocessed) do
              {:ok, {outbound, final_state}} ->
                {:ok, {[{state.socket, Frame.Settings.ack()}] ++ outbound, final_state}}

              {:error, reason} ->
                {:error, reason}
            end
          {:ok, {nil, unprocessed}} ->
            {:ok, {[], %{state | unprocessed: @preface <> unprocessed}}}
          {:ok, {frame, unprocessed}} ->
            {:error, {:protocol_error, "Unexpected frame in client preface"}}
          {:error, reason} ->
            {:error, reason}
        end
      # NOTE length of client preamble is 24 octets
      unprocessed when byte_size(unprocessed) < 24 ->
        {:ok, {[], %{state | unprocessed: unprocessed}}}
      _ ->
      {:error, {:protocol_error, "Client did not send correct preface"}}
    end
  end
  # TODO send first few things in same packet will fail

  # add unprocessed
  # Could call this process frame
  # NOTE endpoint in connected state (accepting continuation or any)
  def receive_packet(state = %__MODULE__{}, packet) do
    case Frame.parse(packet, max_length: 16384) do
      {:ok, {nil, unprocessed}} ->
        {:ok, {[], %{state | unprocessed: unprocessed}}}

      {:ok, {frame, unprocessed}} ->
        case process_frame(frame, state) do
          {:ok, {msgs, new_state}} ->
            :ok

            case receive_packet(new_state, unprocessed) do
              {:ok, {a, b}} ->
                {:ok, {msgs ++ a, b}}
            end
          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_frame(frame = %Frame.Data{}, state = %{status: :normal}) do
    case Stream.receive(Map.get(state.streams, frame.stream_id), frame) do
      _ -> :ok
    end
  end

  defp process_frame(frame = %Frame.Headers{}, state = %{read_status: :normal}) do
    {:ok, {headers, decode_context}} =
      Ace.HPack.decode(frame.header_block_fragment, state.decode_context)

    # check next_id - state.next_remote_stream_id is divisible by two
    next_id = state.next_remote_stream_id

    case frame.stream_id do
      new_id when new_id >= next_id ->
        # NOTE erlang rem returns -1 for negative numerators
        case abs(rem(new_id - next_id, 2)) do
          0 ->
            {:ok, request} = Ace.HTTP2.headers_to_request(headers, frame.end_stream)
            {:ok, worker} = Supervisor.start_child(state.worker_supervisor, [])

            {:ok, {[{worker, request}], %{state | decode_context: decode_context, next_remote_stream_id: frame.stream_id + 2}}}
          1 ->
            {:error, {:protocol_error, "Cannot start stream with peer assigned stream_id"}}
        end
      existing_id ->
        stream = Map.get(state.streams, existing_id, :closed)
    end

    # Stream.from_client
  end

  # id could be odd or even if including push promise
  defp receive_request(request, stream_id, state) do
    # New_id ok
    # existing_id bad but stream would tell you that
    # except needs to be connection level error
  end

  # defp stream_receive(%{}) do
  #
  # end

  # 6.
  defp process_frame(frame = %Frame.PushPromise{}, state = %{status: :normal}) do
    case Stream.receive(Map.get(state.streams, frame.stream_id), frame) do
      _ -> :ok
    end

    case Stream.promise(Map.get(state.streams, frame.stream_id), frame) do
      _ -> :ok
    end
  end

  # 7.
  # TODO could just replace status field with continuation true/false
  defp process_frame(frame = %Frame.Ping{ack: false}, state = %{read_status: :normal}) do
    {:ok, {[Frame.Ping.ack(frame)], state}}
  end

  # establish_stream
  # promised_stream
  # promise_stream
  # new_stream

  defp stream_receive(set, id, headers) do
  end

  defp worker_exited(state, ref, reaons) do
  end

end
