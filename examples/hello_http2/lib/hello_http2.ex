defmodule HomePage do
  use Ace.HTTP2.Stream

  def handle_info({:headers, request}, {connection, config}) do
    IO.inspect(request)

    Ace.HTTP2.send_to_client(connection, {:headers, %{:status => 200, "content-length" => "13"}})
    Ace.HTTP2.send_to_client(connection, {:data, {"Hello, World!", :end}})
    {:noreply, {connection, config}}
  end


end
defmodule HelloHTTP2 do
  def route(%{method: "GET", path: "/"}), do: HomePage
end
