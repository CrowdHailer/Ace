defmodule Ace.HTTP2.Stream do
  @moduledoc false
  alias Ace.HTTP2.{
    # Debt I don't think the stream should know about frames
    Frame
  }

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

  def idle(stream_id, state) do
    {:ok, worker} = Supervisor.start_child(state.stream_supervisor, [])
    monitor = Process.monitor(worker)
    %__MODULE__{
      id: stream_id,
      status: :idle,
      worker: worker,
      monitor: monitor,
      initial_window_size: state.initial_window_size,
      sent: 0,
      incremented: 0,
      buffer: "",
    }
  end

  def outbound_window(stream) do
    (stream.incremented + stream.initial_window_size) - stream.sent
  end

  # TODO rename
  def build_request(headers = [{<<c, _rest::binary>>, _}]) when c != ?: do
    read_headers(headers)
  end
  def build_request([{":status", status} | headers]) do
    case read_headers(headers) do
      {:ok, headers} ->
        {status, ""} = Integer.parse(status)
        {:ok, {status, headers}}
    end
  end
  def build_request(request_headers) do
    build_request(request_headers, {:scheme, :authority, :method, :path})
  end
  def build_request([{":scheme", scheme} | rest], {:scheme, authority, method, path}) do
    case scheme do
      "" ->
        {:error, {:protocol_error, "scheme must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  def build_request([{":authority", authority} | rest], {scheme, :authority, method, path}) do
    case authority do
      "" ->
        {:error, {:protocol_error, "authority must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  def build_request([{":method", method} | rest], {scheme, authority, :method, path}) do
    case method do
      "" ->
        {:error, {:protocol_error, "method must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  def build_request([{":path", path} | rest], {scheme, authority, method, :path}) do
    case path do
      "" ->
        {:error, {:protocol_error, "path must not be empty"}}
      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end
  def build_request([{":" <> psudo, _value} | _rest], _required) do
    case psudo do
      psudo when psudo in ["scheme", "authority", "method", "path"] ->
        {:error, {:protocol_error, "pseudo-header sent amongst normal headers"}}
      other ->
        {:error, {:protocol_error, "unacceptable pseudo-header, :#{other}"}}
    end
  end
  def build_request(headers, request = {scheme, authority, method, path}) do
    if scheme == :scheme or authority == :authority or method == :method or path == :path do
      {:error, {:protocol_error, "All pseudo-headers must be sent"}}
    else
      case read_headers(headers) do
        {:ok, headers} ->
          {:ok, {request, headers}}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def read_headers(raw, acc \\ [])
  def read_headers([], acc) do
    {:ok, Enum.reverse(acc)}
  end
  def read_headers([{":"<>_,_} | _], _acc) do
    {:error, {:protocol_error, "pseudo-header sent amongst normal headers"}}
  end
  def read_headers([{"connection", _} | _rest], _acc) do
    {:error, {:protocol_error, "connection header must not be used with HTTP/2"}}
  end
  def read_headers([{"te", value} | rest], acc) do
    case value do
      "trailers" ->
        read_headers(rest, [{"te", value}, acc])
      _ ->
        {:error, {:protocol_error, "TE header field with any value other than 'trailers' is invalid"}}
    end
  end
  def read_headers([{k, v} | rest], acc) do
    case String.downcase(k) == k do
      true ->
        read_headers(rest, [{k, v}, acc])
      false ->
        {:error, {:protocol_error, "headers must be lower case"}}
    end
  end

  # in idle state can receive only headers and priority
  def consume(stream = %{status: :idle}, message = %{headers: headers, end_stream: end_stream}) do
    case build_request(headers) do
      {:ok, {status_code, headers}} when is_integer(status_code) ->
        status = if end_stream do
          :closed_remote
        else
          :open
        end
        response = Ace.Response.new(status_code, headers, !end_stream)
        forward(stream, response)
        {:ok, {[], %{stream | status: status}}}
      {:ok, _request} ->
        # DEBT send Ace.Request not headers
        status = if end_stream do
          :closed_remote
        else
          :open
        end
        forward(stream, message)
        {:ok, {[], %{stream | status: status}}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume(%{status: :idle}, {:reset, _reason}) do
    {:error, {:protocol_error, "RstStream frame received on a stream in idle state. (RFC7540 5.1)"}}
  end
  def consume(%{status: :idle}, %{data: _}) do
    {:error, {:protocol_error, "DATA frame received on a stream in idle state. (RFC7540 5.1)"}}
  end
  def consume(%{status: :idle}, {:window_update, _}) do
    {:error, {:protocol_error, "WindowUpdate frame received on a stream in idle state. (RFC7540 5.1)"}}
  end

  def consume(stream = %{status: :reserved_remote}, message = %{headers: headers, end_stream: end_stream}) do
    stream = if end_stream do
      %{stream | status: :closed}
    else
      %{stream | status: :closed_local}
    end
    {:ok, {code, headers}} = build_request(headers)
    response = Ace.Response.new(code, headers, !end_stream)
    forward(stream, response)
    {:ok, {[], stream}}
  end
  def consume(stream = %{status: :open}, message = %{data: _, end_stream: end_stream}) do
    stream = if end_stream do
      %{stream | status: :closed_remote}
    else
      stream
    end
    forward(stream, message)
    {:ok, {[], stream}}
  end
  def consume(stream = %{status: :open}, message = %{headers: headers, end_stream: end_stream}) do
    case build_request(headers) do
      {:ok, {code, headers}} when is_integer(code) ->
        response = Ace.Response.new(code, headers, !end_stream)
        forward(stream, response)
        {:ok, {[], stream}}
      {:ok, _trailers} ->
        # TODO send trailers
        if end_stream do
          stream = %{stream | status: :closed_remote}
          forward(stream, message)
          {:ok, {[], stream}}
        else
          # DEBT could be stream error
          {:error, {:protocol_error, "Trailers must end a stream"}}
        end
      {:error, reason} ->
        {:error, reason}
    end

  end
  def consume(stream = %{status: :open}, {:window_update, increment}) do
    increase_window(stream, increment)
  end
  def consume(stream = %{status: :open}, {:reset, reason}) do
    forward(stream, {:reset, reason})
    # TODO reset stream
    {:ok, {[], %{stream | status: :closed}}}
  end

  def consume(stream = %{status: :closed_local}, message = %{headers: headers, end_stream: end_stream}) do
    case build_request(headers) do
      {:ok, {code, headers}} when is_integer(code) ->
        response = Ace.Response.new(code, headers, !end_stream)
        forward(stream, response)
        {:ok, {[], stream}}
      {:ok, _trailers} ->
        # TODO send trailers
        if end_stream do
          stream = %{stream | status: :closed_remote}
          forward(stream, message)
          {:ok, {[], stream}}
        else
          # DEBT could be stream error
          {:error, {:protocol_error, "Trailers must end a stream"}}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
  def consume(stream = %{status: :closed_local}, message = %{data: _, end_stream: end_stream}) do
    stream = if end_stream do
      %{stream | status: :closed}
    else
      stream
    end
    forward(stream, message)
    {:ok, {[], stream}}
  end
  def consume(stream = %{status: :closed_local}, {:reset, reason}) do
    forward(stream, {:reset, reason})
    {:ok, {[], %{stream | status: :closed}}}
  end
  def consume(stream = %{status: :closed_local}, {:promise, promise}) do
    forward(stream, {:promise, promise})
    IO.inspect(promise)
    {:ok, {[], stream}}
  end
  def consume(%{status: :closed_remote}, %{headers: _}) do
    {:error, {:stream_closed, "Headers received on closed stream"}}
  end
  def consume(%{status: :closed_remote}, %{data: _}) do
    {:error, {:stream_closed, "Data received on closed stream"}}
  end
  def consume(stream = %{status: :closed_remote}, {:window_update, increment}) do
    increase_window(stream, increment)
  end
  def consume(stream = %{status: :closed_remote}, {:reset, _reason}) do
    # TODO flow control
    {:ok, {[], %{stream | status: :closed}}}
  end
  def consume(%{status: :closed}, %{headers: _}) do
    {:error, {:protocol_error, "headers received on closed stream"}}
  end
  def consume(%{status: :closed}, %{data: _}) do
    {:error, {:protocol_error, "Data received on closed stream"}}
  end
  def consume(stream = %{status: :closed}, {:reset, _reason}) do
    {:ok, {[], stream}}
  end
  def consume(stream = %{status: :closed}, {:window_update, increment}) do
    increase_window(stream, increment)
  end

  def terminate(stream = %{status: :closed}, :normal) do
    {[], %{stream | status: :closed, worker: nil, monitor: nil}}
  end
  # I think even if the reason is normal we should mark an error because the handler should have sent an end stream message
  def terminate(stream, _reason) do
    rst_frame = Frame.RstStream.new(stream.id, :internal_error)
    {[rst_frame], %{stream | status: :closed, worker: nil, monitor: nil}}
  end

  defp increase_window(stream, increment) do
    new_incremented = stream.incremented + increment
    if new_incremented + stream.initial_window_size <= 2_147_483_647 do
      {:ok, {[], %{stream | incremented: new_incremented}}}
    else
      rst_frame = Frame.RstStream.new(stream.id, :flow_control_error)
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
