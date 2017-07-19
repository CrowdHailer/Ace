defmodule HelloHTTP2 do
  defmodule StreamHandler do
    use GenServer
    def start_link(conf) do
      GenServer.start_link(__MODULE__, conf)
    end

    def handle_info({stream, %{headers: headers, end_stream: true}}, conf) do
      IO.inspect(headers)
      headers = %{
        ":status" => "200",
        "content-length" => "13"
      }
      preface = %{
        headers: headers,
        end_stream: false
      }
      Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
      data = %{
        data: "Hello, World!",
        end_stream: true
      }
      Ace.HTTP2.StreamHandler.send_to_client(stream, data)
      Process.sleep(100_000)
      {:stop, :normal, conf}
    end
  end
end
