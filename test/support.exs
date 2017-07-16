defmodule HomePage do
  use Ace.HTTP2.Stream

  # Maybe we want to use a GenServer.call when passing messages back to connection for back pressure.
  # Need to send back a reference to the stream_id
  def handle_info({:headers, request}, {connection, config}) do
    IO.inspect(request)
    # Connection.stream({pid, ref}, headers/data/push or update etc)

    # response = handle_request(request, Response.new(), config)
    # {[parts], response} = Response.process(response)
    # |> IO.inspect
    # Send {":status" => "200"}
    Ace.HTTP2.send_to_client(connection, {:headers, %{:status => 200, "content-length" => "13"}})
    Ace.HTTP2.send_to_client(connection, {:data, {"Hello, World!", :end}})
    {:noreply, {connection, config}}
  end

  def handle_request(request, response, config) do
    IO.inspect(request)
    IO.inspect(config)
    response
    |> Response.set_status(200) # TODO use atom
    |> Response.put_header("content-length", "13")
    |> Response.send_data("Hello, World!")
    |> Response.finish()
  end


end

defmodule CreateAction do
  use GenServer

  def start_link(connection, config) do
    GenServer.start_link(__MODULE__, {connection, config})
  end

  def handle_info({:headers, request}, {connection, config}) do
    IO.inspect(request)
    {:noreply, {connection, config}}
  end

  def handle_info({:data, data}, {connection, config}) do
    IO.inspect("data")
    IO.inspect(data)
    Ace.HTTP2.send_to_client(connection, {:headers, %{:status => 201, "content-length" => "0"}})
    {:noreply, {connection, config}}
  end

end

defmodule Support do
  def read_next(connection, timeout \\ :infinity) do
    case :ssl.recv(connection, 9, timeout) do
      {:ok, <<length::24, type::8, flags::binary-size(1), 0::1, stream_id::31>>} ->
        case length do
          0 ->
            Ace.HTTP2.Frame.decode({type, flags, stream_id, ""})
          length ->
            {:ok, payload} = :ssl.recv(connection, length, timeout)
            Ace.HTTP2.Frame.decode({type, flags, stream_id, payload})
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_frame(connection, frame) do
    :ssl.send(connection, Ace.HTTP2.Frame.serialize(frame))
  end

  def start_server(app, port \\ 0) do
    certfile =  Path.expand("ace/tls/cert.pem", __DIR__)
    keyfile =  Path.expand("ace/tls/key.pem", __DIR__)
    options = [
      active: false,
      mode: :binary,
      packet: :raw,
      certfile: certfile,
      keyfile: keyfile,
      reuseaddr: true,
      alpn_preferred_protocols: ["h2", "http/1.1"]
    ]
    {:ok, listen_socket} = :ssl.listen(0, options)
    {:ok, server} = Ace.HTTP2.start_link(listen_socket, app)
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {server, port}
  end

  def open_connection(port) do
    {:ok, connection} = :ssl.connect('localhost', port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)
    connection
  end
end
