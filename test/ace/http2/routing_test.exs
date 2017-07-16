defmodule Ace.HTTP2RoutingTest do
  use ExUnit.Case

  setup do
    certfile =  Path.expand("../../ace/tls/cert.pem", __DIR__)
    keyfile =  Path.expand("../../ace/tls/key.pem", __DIR__)
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
    {:ok, server} = Ace.HTTP2.start_link(listen_socket, {__MODULE__, %{test_pid: self}})
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {:ok, connection} = :ssl.connect('localhost', port, [
      mode: :binary,
      packet: :raw,
      active: :false,
      alpn_advertised_protocols: ["h2"]]
    )
    {:ok, "h2"} = :ssl.negotiated_protocol(connection)
    payload = [
      Ace.HTTP2.preface(),
      Ace.HTTP2.Frame.Settings.new() |> Ace.HTTP2.Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Ace.HTTP2.Frame.Settings{ack: true}} == Support.read_next(connection)
    {:ok, %{client: connection}}
  end

  alias Ace.HTTP2.Request

  defmodule HomePage do
    use GenServer

    def start_link(connection, config) do
      GenServer.start_link(__MODULE__, {connection, config})
    end

    # Maybe we want to use a GenServer.call when passing messages back to connection for back pressure.
    # Need to send back a reference to the stream_id
    def handle_info({:headers, request}, {connection, config}) do
      IO.inspect(request)
      # Connection.stream({pid, ref}, headers/data/push or update etc)

      Ace.HTTP2.send_to_client(connection, {:headers, %{:status => 200, "content-length" => "13"}})
      Ace.HTTP2.send_to_client(connection, {:data, {"Hello, World!", :end}})
      {:noreply, {connection, config}}
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

  def route(%{method: "GET", path: "/"}) do
    HomePage
  end
  def route(%{method: "POST", path: "/"}) do
    CreateAction
  end

  # Sending without required header is an error
  test "sending unpadded headers", %{client: connection} do
    request = %Request{
      scheme: :https,
      authority: "example.com",
      method: :GET,
      path: "/",
      headers: %{"content-length" => "0"}
    }

    headers = Request.to_headers(request)
    |> IO.inspect
    {:ok, table} = HPack.Table.start_link(1_000)
    header_block_fragment = HPack.encode(headers, table)
    |> IO.inspect

    size = :erlang.iolist_size(header_block_fragment)

    flags = <<0::5, 1::1, 0::1, 1::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, header_block_fragment::binary>>)
    Process.sleep(2_000)
    # TODO test 200 response
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)

    assert {:ok, %{data: "Hello, World!"}} = Support.read_next(connection, 2_000)
  end

  test "sending padded headers", %{client: connection} do
    request = %Request{
      scheme: :https,
      authority: "example.com",
      method: :GET,
      path: "/",
      headers: %{"content-length" => "0"}
    }

    headers = Request.to_headers(request)
    |> IO.inspect
    {:ok, table} = HPack.Table.start_link(1_000)
    header_block_fragment = HPack.encode(headers, table)
    |> IO.inspect

    payload = Ace.HTTP2.Frame.pad_data(header_block_fragment, 2)

    size = :erlang.iolist_size(payload)

    flags = <<0::4, 1::1, 1::1, 0::1, 1::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, payload::binary>>)
    Process.sleep(2_000)
    # TODO test 200 response header
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    assert {:ok, %{data: "Hello, World!"}} = Support.read_next(connection, 2_000)
  end

  test "send post with data", %{client: connection} do

    {:ok, encode_table} = HPack.Table.start_link(1_000)
    {:ok, decode_table} = HPack.Table.start_link(1_000)
    body = HPack.encode([{":method", "POST"}, {":scheme", "https"}, {":path", "/"}], encode_table)

    size = :erlang.iolist_size(body)

    # <<_, _, priority, _, padded, end_headers, _, end_stream>>
    flags = <<0::5, 1::1, 0::1, 0::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    data_frame = Ace.HTTP2.Frame.Data.new(1, "Upload", true) |> Ace.HTTP2.Frame.Data.serialize()
    :ssl.send(connection, data_frame)
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    assert = [{":status", "201"}, {"content-length", "0"}] == HPack.decode(hbf, decode_table)
  end

  @tag :skip
  test "send post with padded data", %{client: connection} do

    {:ok, decode_table} = HPack.Table.start_link(1_000)
    {:ok, encode_table} = HPack.Table.start_link(1_000)
    body = HPack.encode([{":method", "POST"}, {":scheme", "https"}, {":path", "/"}], encode_table)

    size = :erlang.iolist_size(body)

    # <<_, _, priority, _, padded, end_headers, _, end_stream>>
    flags = <<0::5, 1::1, 0::1, 0::1>>
    # Client initated streams must use odd stream identifiers
    :ssl.send(connection, <<size::24, 1::8, flags::binary, 0::1, 1::31, body::binary>>)
    data_frame = Ace.HTTP2.Frame.Data.new(1, "Upload", pad_length: 2, end_stream: true)
    :ssl.send(connection, data_frame)
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    assert = [{":status", "201"}, {"content-length", "0"}] == HPack.decode(hbf, decode_table)
  end
end
