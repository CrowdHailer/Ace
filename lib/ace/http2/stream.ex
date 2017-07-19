defmodule Ace.HTTP2.Stream do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      def start_link(connection, config) do
        GenServer.start_link(__MODULE__, {connection, config})
      end
    end
  end

  # # connection {conn_pid, stream_id, other_ref}
  # defstruct [
  #   id: nil,
  #   worker: nil # {pid, monitor}
  # ]
  #
  # def idle(id) do
  #   %__MODULE__{id: id}
  # end
  #
  # def recv_h(%{worker: nil}, headers) do
  #   handler_mod = route(headers)
  #   {pid, ref} = start_worker(handler_mod, headers)
  # end
  #
  # def recv_data(stream, data) do
  #
  # end
  #
  # # calculate from stream id
  # def client do
  #
  # end
end
