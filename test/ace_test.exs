defmodule AceTest do
  use ExUnit.Case
  setup do
    # Setup a server
    {:ok, %{port: :port}}
  end
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  def parse_frame(<<length :: 24, type :: 8, flags :: 8, 0 :: 1, id :: 31>> <> rest) do
    # IO.inspect(length)
    # IO.inspect(id)
    # IO.inspect(type)
    # IO.inspect(rest)
    <<payload :: binary - size(length), rest :: bitstring>> = rest
    {type, payload, rest}
  end

  def loop(socket, buffer \\ "") do
    :ssl.setopts(socket, [active: :once])
    IO.inspect(buffer)
    {_, _, rest} =parse_frame(buffer)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    {_, _, rest} = parse_frame(rest)
    |> IO.inspect
    receive do
      {:ssl, ^socket, @preface <> data} ->
        parse_frame(data)
        |> IO.inspect
        IO.inspect(data)
        loop(socket)
    end
  end

  test "get a single response" do
    preface = @preface
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
      {:ok, "h2"} = :ssl.negotiated_protocol(socket)
      IO.inspect("connected over http2")
      :ssl.setopts(socket, [active: :once])
      # Don't need to send preface immediatly
      :ssl.send(socket, <<0 :: 24, 4 :: 8, 0 :: 8, 0 :: 1, 0 :: 31>>)
      receive do
        {:ssl, ^socket, @preface <> buffer} ->
          loop(socket, buffer)
        # any ->
        #   IO.inspect(any)
        #   loop(socket, "")
      after
        1_000 ->
          receive do
            any ->
              IO.puts("Fail")
              IO.inspect(any)
          end
      end
    end)
    :timer.sleep(1_000)
    # {:ok, socket} = :ssl.connect('localhost', 8443, [
    #   mode: :binary,
    #   packet: :raw,
    #   active: :false,
    #   alpn_advertised_protocols: ["h2"]])
    # |> IO.inspect
    # IO.inspect(:ssl.negotiated_protocol(socket))
    # :ssl.send(socket, preface <> <<4 :: 24, 4 :: 8, 0 :: 8, 0 :: 1, 0 :: 31>> <> "four")
    # :ssl.recv(socket, 0, 1_000)
    # |> IO.inspect
    Task.await(task, 60_000)
  end
end
