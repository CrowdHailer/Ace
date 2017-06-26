defmodule AceTest do
  use ExUnit.Case
  setup do
    # Setup a server
    {:ok, %{port: :port}}
  end

  test "get a single response" do
    preface = "PRI * HTTP/2.0\r\n\r\nSM: Value\r\n\r\n"

    Application.ensure_all_started(:crypto)
    |> IO.inspect
    certfile =  Path.expand("./ace/tls/cert.pem", __DIR__)
    keyfile =  Path.expand("./ace/tls/key.pem", __DIR__)
    task = Task.async(fn() ->
      # Ace.start_link(8443, [certfile: certfile, keyfile: keyfile])
      options = [
        active: false,
        mode: :binary,
        packet: :raw,
        certfile: certfile,
        keyfile: keyfile,
        reuseaddr: true,
        alpn_preferred_protocols: ["h2", "http/1.1"]
      ]
      {:ok, listen_socket} = :ssl.listen(8443, options)
      IO.puts("Server listening")
      {:ok, socket} = :ssl.transport_accept(listen_socket)
      IO.puts("Server accepted")
      :ok = :ssl.ssl_accept(socket)
      IO.inspect(:ssl.negotiated_protocol(socket))
      :ssl.setopts(socket, [active: :once])
      receive do
        data ->
          IO.inspect(data)
      end
      receive do
        data ->
          IO.inspect(data)
      end
      :timer.sleep(5_000)
    end)
    :timer.sleep(1_000)
    {:ok, socket} = :ssl.connect('localhost', 8443, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]])
    |> IO.inspect
    IO.inspect(:ssl.negotiated_protocol(socket))
    :ssl.send(socket, preface)
    Task.await(task, 60_000)
  end
end
