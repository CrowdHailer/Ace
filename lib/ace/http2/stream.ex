defmodule Ace.HTTP2.Stream do
  alias Ace.HTTP2.{
    # Debt I don't think the stream should know about frames
    Frame
  }

  @enforce_keys [:stream_id, :status, :worker, :monitor]
  defstruct @enforce_keys

  def idle(stream_id, state) do
    {:ok, worker} = Supervisor.start_child(state.stream_supervisor, [])
    monitor = Process.monitor(worker)
    %__MODULE__{
      stream_id: stream_id,
      status: :idle,
      worker: worker,
      monitor: monitor
    }
  end

  # in idle state can receive only headers and priority
  def consume(stream = %{status: :idle}, message = %{headers: _, end_stream: end_stream}) do
    status = if end_stream do
      :closed_remote
    else
      :open
    end
    forward(stream, message)
    {:ok, {[], %{stream | status: status}}}
  end
  def consume(%{status: :idle}, :reset) do
    {:error, {:protocol_error, "RstStream frame received on a stream in idle state. (RFC7540 5.1)"}}
  end
  def consume(%{status: :idle}, %{data: _}) do
    {:error, {:protocol_error, "DATA frame received on a stream in idle state. (RFC7540 5.1)"}}
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
  def consume(stream = %{status: :open}, message = %{headers: _, end_stream: end_stream}) do
    stream = if end_stream do
      %{stream | status: :closed_remote}
    else
      stream
    end
    forward(stream, message)
    {:ok, {[], stream}}
  end

  def consume(stream = %{status: :closed_remote}, %{headers: _}) do
    rst_frame = Frame.RstStream.new(stream.stream_id, :stream_closed)
    {:ok, {[rst_frame], %{stream | status: :closed}}}
  end
  def consume(stream = %{status: :closed_remote}, %{data: _}) do
    rst_frame = Frame.RstStream.new(stream.stream_id, :stream_closed)
    {:ok, {[rst_frame], %{stream | status: :closed}}}
  end

  def terminate(stream = %{status: :closed}, :normal) do
    {[], %{stream | status: :closed, worker: nil, monitor: nil}}
  end
  # I think even if the reason is normal we should mark an error because the handler should have sent an end stream message
  def terminate(stream, _reason) do
    rst_frame = Frame.RstStream.new(stream.stream_id, :internal_error)
    {[rst_frame], %{stream | status: :closed, worker: nil, monitor: nil}}
  end

  defp forward(stream, message) do
    stream_ref = {:stream, self(), stream.stream_id, stream.monitor}
    # # Maybe send with same ref as used for reply
    send(stream.worker, {stream_ref, message})
  end
end
