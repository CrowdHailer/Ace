defmodule Ace.HTTP2.Stream do
  @moduledoc false

  @enforce_keys [
    :id,
    :status,
    :worker,
    :monitor,
    :initial_window_size,
    :sent,
    :incremented,
    :buffer
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

  defp new(stream_id, status, worker, initial_window_size) do
    monitor = Process.monitor(worker)
    %__MODULE__{
      id: stream_id,
      status: status,
      worker: worker,
      monitor: monitor,
      initial_window_size: initial_window_size,
      sent: 0,
      incremented: 0,
      buffer: "",
    }
  end

  def outbound_window(stream) do
    (stream.incremented + stream.initial_window_size) - stream.sent
  end

  def send_request(stream, request) do
    case stream.status do
      {:idle, :idle} ->
        headers = Ace.HTTP2.request_to_headers(request)
        new_status = {{:open, 0}, :idle}
        new_stream = %{stream | status: new_status}
        case request.body do
          true ->
            {:ok, {[%{headers: headers, end_stream: false}], new_stream}}
          false ->
            {:ok, {[%{headers: headers, end_stream: true}], process_send_end_stream(new_stream)}}
          body ->
            send_data(stream, body, true, [%{headers: headers, end_stream: false}])
        end
    end
  end
  def send_response(stream, response) do
    response = if response.body == "" do
      %{response | body: false}
    else
      response
    end
    case stream.status do
      {:idle, :idle} ->
        {:error, :dont_send_response_first}
      {:closed, :closed} ->
        # DEBT happens to reset stream, notify worker data not sent
        {:ok, {[], stream}}
      {:idle, remote} ->
        headers = Ace.HTTP2.response_to_headers(response)
        new_status = {{:open, 0}, remote}
        new_stream = %{stream | status: new_status}
        case response.body do
          true ->
            {:ok, {[%{headers: headers, end_stream: false}], new_stream}}
          false ->
            {:ok, {[%{headers: headers, end_stream: true}], process_send_end_stream(new_stream)}}
          body ->
            send_data(new_stream, body, true, [%{headers: headers, end_stream: false}])
        end
      {:reserved, :closed} ->
        headers = Ace.HTTP2.response_to_headers(response)
        new_status = {{:open, 0}, :closed}
        new_stream = %{stream | status: new_status}
        case response.body do
          true ->
            {:ok, {[%{headers: headers, end_stream: false}], new_stream}}
          false ->
            {:ok, {[%{headers: headers, end_stream: true}], process_send_end_stream(new_stream)}}
          body ->
            send_data(new_stream, body, true, [%{headers: headers, end_stream: false}])
        end
    end
  end

  def send_data(stream, data, end_stream, pending \\ []) do
    case stream.status do
      {{:open, sent}, remote} ->
        new_status = {{:open, sent + :erlang.iolist_size(data)}, remote}
        new_stream = %{stream | status: new_status}
        message = %{data: data, end_stream: end_stream}
        final_stream = if end_stream do
          process_send_end_stream(new_stream)
        else
          new_stream
        end
        {:ok, {pending ++ [message], final_stream}}
    end
  end

  def send_trailers(stream, trailers) do
    new_status = process_send_end_stream(stream)
    new_stream = %{stream | status: new_status}
    {:ok, {[%{headers: trailers, end_stream: true}], new_stream}}
  end

  def send_reset(stream, error, _debug) do
    # TODO debug never used
    new_status = {:closed, :closed}
    new_stream = %{stream | status: new_status}
    {:ok, {[Ace.HTTP2.Frame.RstStream.new(stream.id, error)], new_stream}}
  end

  defp process_send_end_stream(stream) do
    case stream.status do
      {{:open, _}, remote} ->
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
        {:ok, {[], new_stream}}
    end
  end
  def receive_headers(stream, headers, end_stream) do
    case stream.status do
      {:idle, :idle} ->
        {:ok, request} = Ace.HTTP2.headers_to_request(headers, end_stream)
        forward(stream, request)
        {:ok, {[], {:idle, {:open, 0}}}}
      {local, :idle} ->
        {:ok, response} = Ace.HTTP2.headers_to_response(headers, end_stream)
        forward(stream, response)
        {:ok, {[], {local, {:open, 0}}}}
      {local, :reserved} ->
        {:ok, response} = Ace.HTTP2.headers_to_response(headers, end_stream)
        forward(stream, response)
        {:ok, {[], {local, {:open, 0}}}}
      {local, {:open, _}} ->
        # check end_stream
        trailers = Ace.HTTP2.headers_to_trailers(headers)
        forward(stream, trailers)
        # TODO add data nonzero
        {:ok, {[], {local, {:open, 0}}}}
      {_local, :closed} ->
        {:error, {:stream_closed, "Headers received on closed stream"}}
    end
    |> case do
      {:ok, {messages, new_status}} ->
        new_stream = %{stream | status: new_status}
        {messages2, final_stream} = if end_stream do
          process_received_end_stream(new_stream)
        else
          {:ok, {messages, new_stream}}
        end
        {messages ++ messages2, final_stream}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def receive_promise(original, promised, request) do
    promised_stream_ref = {:stream, self(), promised.id, promised.monitor}
    forward(original, {:promise, {promised_stream_ref, request}})
    {:ok, {[], original}}
  end

  def receive_data(stream, data, end_stream) do
    new_status = case stream.status do
      {local, {:open, receive_data}} ->
        forward(stream, %{data: data, end_stream: end_stream})
        new_reveiced_data = receive_data + :erlang.iolist_size(data)
        {local, {:open, new_reveiced_data}}
      # errors
      {:idle, :idle} ->
        {:error, {:protocol_error, "DATA frame received on a stream in idle state. (RFC7540 5.1)"}}
      {_, :closed} ->
        {:error, {:stream_closed, "Data received on closed stream"}}
    end
    new_stream = %{stream | status: new_status}
    if end_stream do
      process_received_end_stream(new_stream)
    else
      {:ok, {[], new_stream}}
    end
  end

  def receive_window_update(stream, increment) do
    case stream.status do
      {:idle, :idle} ->
        {:error, {:protocol_error, "WindowUpdate frame received on a stream in idle state. (RFC7540 5.1)"}}
      {:idle, _remote} ->
        increase_window(stream, increment)
      {{:open, _}, _remote} ->
        increase_window(stream, increment)
    end
  end

  def process_received_end_stream(stream) do
    new_status = case stream.status do
      {local, {:open, _}} ->
        {local, :closed}
    end
    {:ok, {[], %{stream | status: new_status}}}
  end

  def receive_reset(stream, reason) do
    case stream.status do
      {:idle, :idle} ->
        {:error, {:protocol_error, "RstStream frame received on a stream in idle state. (RFC7540 5.1)"}}
      {:closed, :closed} ->
        {:ok, {[], stream}}
      {_, _} ->
        forward(stream, {:reset, reason})
        {:ok, {[], %{stream | status: {:closed, :closed}}}}
    end
  end

  def terminate(stream = %{status: :closed}, :normal) do
    {[], %{stream | status: :closed, worker: nil, monitor: nil}}
  end
  # I think even if the reason is normal we should mark an error because the handler should have sent an end stream message
  def terminate(stream, _reason) do
    rst_frame = Ace.HTTP2.Frame.RstStream.new(stream.id, :internal_error)
    {[rst_frame], %{stream | status: :closed, worker: nil, monitor: nil}}
  end

  defp increase_window(stream, increment) do
    new_incremented = stream.incremented + increment
    if new_incremented + stream.initial_window_size <= 2_147_483_647 do
      {:ok, {[], %{stream | incremented: new_incremented}}}
    else
      rst_frame = Ace.HTTP2.Frame.RstStream.new(stream.id, :flow_control_error)
      # TODO test stream was reset by error
      {:ok, {[rst_frame], stream}}
    end
  end

  defp forward(stream, message) do
    stream_ref = {:stream, self(), stream.id, stream.monitor}
    # # Maybe send with same ref as used for reply
    send(stream.worker, {stream_ref, message})
  end
end
