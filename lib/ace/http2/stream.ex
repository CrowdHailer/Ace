defmodule Ace.HTTP2.Stream do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      def start_link(connection, config) do
        GenServer.start_link(__MODULE__, {connection, config})
      end
    end
  end
end
