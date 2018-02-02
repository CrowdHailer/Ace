defmodule Ace.HTTP2.Stream do
  @moduledoc false

  @max_stream_window 2_147_483_647

  @enforce_keys [
    :id,
    :status,
    :worker,
    :monitor,
    :initial_window_size,
    :incremented,
    :sent,
    :queue
  ]
  defstruct @enforce_keys

  def idle(stream_id, worker, initial_window_size) do
    new(stream_id, {:idle, :idle}, worker, initial_window_size)
  end

  def reserve(stream_id, worker, initial_window_size) do
    new(stream_id, {:reserved, :closed}, worker, initial_window_size)
  end

  def reserved(stream_id, worker, initial_window_size) do
    new(stream_id, {:closed, :reserved}, worker, initial_window_size)
  end

  defp new(stream_id, status, worker, initial_window_size) when is_integer(initial_window_size) do
    monitor = Process.monitor(worker)

    %__MODULE__{
      id: stream_id,
      status: status,
      worker: worker,
      monitor: monitor,
      initial_window_size: initial_window_size,
      incremented: 0,
      sent: 0,
      queue: []
    }
  end

  def outbound_window(stream) do
    stream.incremented + stream.initial_window_size - stream.sent
  end

  def send_request(stream, request = %{body: body}) when is_boolean(body) do
    case stream.status do
      {:idle, :idle} ->
        new_status = {:open, :idle}
        headers = Ace.HTTP2.request_to_headers(request)
        queue = [%{headers: headers, end_stream: !body}]
        new_stream = %{stream | status: new_status, queue: stream.queue ++ queue}
        {:ok, new_stream}

      _ ->
        {:error, :request_sent}
    end
  end

  def send_request(stream, request = %{body: ""}) do
    send_request(stream, %{request | body: false})
  end

  def send_request(stream, request = %{body: body}) do
    case send_request(stream, %{request | body: true}) do
      {:ok, stream_with_headers} ->
        {:ok, new_stream} = send_data(stream_with_headers, Raxx.data(body))
        send_tail(new_stream, Raxx.tail())

      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_response(stream, response = %{body: body}) when is_boolean(body) do
    case stream.status do
      {:idle, :idle} ->
        {:error, :dont_send_response_first}

      {:closed, :closed} ->
        # DEBT happens to reset stream, notify worker data not sent
        {:ok, stream}

      {:idle, remote} ->
        new_status = {:open, remote}
        headers = Ace.HTTP2.response_to_headers(response)
        queue = [%{headers: headers, end_stream: !body}]
        new_stream = %{stream | status: new_status, queue: stream.queue ++ queue}
        {:ok, new_stream}

      {:reserved, :closed} ->
        new_status = {:open, :closed}
        headers = Ace.HTTP2.response_to_headers(response)
        queue = [%{headers: headers, end_stream: !body}]
        new_stream = %{stream | status: new_status, queue: stream.queue ++ queue}
        {:ok, new_stream}
    end
  end

  def send_response(stream, response = %{body: ""}) do
    send_response(stream, %{response | body: false})
  end

  def send_response(stream, response = %{body: body}) do
    case send_response(stream, %{response | body: true}) do
      {:ok, stream_with_headers} ->
        {:ok, new_stream} = send_data(stream_with_headers, Raxx.data(body))
        send_tail(new_stream, Raxx.tail([]))

      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_data(stream, data = %Raxx.Data{}) do
    case stream.status do
      {:open, _remote} ->
        queue = [data]
        new_stream = %{stream | queue: stream.queue ++ queue}

        {:ok, new_stream}

      {:closed, :closed} ->
        {:ok, stream}
    end
  end

  def send_tail(stream, tail = %Raxx.Tail{}) do
    new_stream = process_send_end_stream(stream)
    queue = stream.queue ++ [tail]
    new_stream = %{new_stream | queue: queue}
    {:ok, new_stream}
  end

  # Sending a reset drops the queue
  def send_reset(stream, error) do
    new_status = {:closed, :closed}
    queue = [{:reset, error}]
    new_stream = %{stream | status: new_status, queue: queue}
    {:ok, new_stream}
  end

  defp process_send_end_stream(stream) do
    case stream.status do
      {:open, remote} ->
        new_status = {:closed, remote}
        %{stream | status: new_status}
    end
  end

  def receive_headers(stream, request) do
    case stream.status do
      {:reserved, :closed} ->
        forward(stream, request)
        new_status = {:reserved, :closed}
        new_stream = %{stream | status: new_status}
        {:ok, new_stream}
    end
  end

  def receive_headers(stream, headers, end_stream) do
    case stream.status do
      {:idle, :idle} ->
        case Ace.HTTP2.headers_to_request(headers, end_stream) do
          {:ok, request} ->
            forward(stream, request)
            {:ok, {:idle, :open}}

          {:error, reason} ->
            {:error, reason}
        end

      {local, :idle} ->
        {:ok, response} = Ace.HTTP2.headers_to_response(headers, end_stream)
        forward(stream, response)
        {:ok, {local, :open}}

      {local, :reserved} ->
        {:ok, response} = Ace.HTTP2.headers_to_response(headers, end_stream)
        forward(stream, response)
        {:ok, {local, :open}}

      {local, :open} ->
        # check end_stream
        if end_stream do
          trailers = Ace.HTTP2.headers_to_trailers(headers)
          trailers = %Raxx.Tail{headers: trailers.headers}
          forward(stream, trailers)
          # Open but will be closed by handle process_received_end_stream
          {:ok, {local, :open}}
        else
          {:error, {:protocol_error, "trailers must end the stream"}}
        end

      {_local, :closed} ->
        {:error, {:stream_closed, "Headers received on closed stream"}}
    end
    |> case do
      {:ok, new_status} ->
        new_stream = %{stream | status: new_status}

        {:ok, final_stream} =
          if end_stream do
            process_received_end_stream(new_stream)
          else
            {:ok, new_stream}
          end

        {:ok, final_stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def receive_promise(original, promised, request) do
    promised_stream_ref = {:stream, self(), promised.id, promised.monitor}
    forward(original, {:promise, {promised_stream_ref, request}})
    {:ok, original}
  end

  def receive_data(stream, data, end_stream) do
    new_status =
      case stream.status do
        {local, :open} ->
          forward(stream, %Raxx.Data{data: data})

          if end_stream do
            forward(stream, Raxx.tail())
          end

          {local, :open}

        # errors
        {:idle, :idle} ->
          {
            :error,
            {:protocol_error, "DATA frame received on a stream in idle state. (RFC7540 5.1)"}
          }

        {_, :closed} ->
          {:error, {:stream_closed, "Data received on closed stream"}}
      end

    new_stream = %{stream | status: new_status}

    if end_stream do
      process_received_end_stream(new_stream)
    else
      {:ok, new_stream}
    end
  end

  def receive_window_update(stream, increment) do
    case stream.status do
      {:idle, :idle} ->
        {
          :error,
          {
            :protocol_error,
            "WindowUpdate frame received on a stream in idle state. (RFC7540 5.1)"
          }
        }

      {_local, _remote} ->
        increase_window(stream, increment)
    end
  end

  def process_received_end_stream(stream) do
    case stream.status do
      {local, :open} ->
        new_status = {local, :closed}
        {:ok, %{stream | status: new_status}}

      _ ->
        {:error, {:protocol_error, "Unexpected stream message"}}
    end
  end

  def receive_reset(stream, reason) do
    case stream.status do
      {:idle, :idle} ->
        {
          :error,
          {:protocol_error, "RstStream frame received on a stream in idle state. (RFC7540 5.1)"}
        }

      {:closed, :closed} ->
        {:ok, stream}

      {_, _} ->
        forward(stream, {:reset, reason})
        {:ok, %{stream | status: {:closed, :closed}}}
    end
  end

  defp increase_window(stream, increment) do
    new_stream = %{stream | incremented: stream.incremented + increment}

    if outbound_window(new_stream) <= @max_stream_window do
      {:ok, new_stream}
    else
      {:error, {:flow_control_error, "Stream window was increased beyond maximum"}}
    end
  end

  defp forward(stream, message) do
    stream_ref = {:stream, self(), stream.id, stream.monitor}
    # # Maybe send with same ref as used for reply
    send(stream.worker, {stream_ref, message})
  end
end
