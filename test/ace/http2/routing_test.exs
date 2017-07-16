defmodule Ace.HTTP2RoutingTest do
  use ExUnit.Case

  alias Ace.HTTP2.{
    Request,
    Response,
    Frame
  }

  def route(%{method: "GET", path: "/"}), do: HomePage
  def route(%{method: "POST", path: "/"}), do: CreateAction

  setup do
    {server, port} = Support.start_server({__MODULE__, %{test_pid: self()}})
    connection = Support.open_connection(port)
    payload = [
      Ace.HTTP2.preface(),
      Frame.Settings.new() |> Frame.Settings.serialize(),
    ]
    :ssl.send(connection, payload)
    assert {:ok, %Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Frame.Settings{ack: true}} == Support.read_next(connection)
    {:ok, %{client: connection}}
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

    {:ok, table} = HPack.Table.start_link(1_000)
    header_block = Request.compress(request, table)
    headers_frame = Frame.Headers.new(1, header_block, true, true)

    Support.send_frame(connection, headers_frame)
    # TODO test 200 response
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    {:ok, table} = HPack.Table.start_link(1_000)
    HPack.decode(hbf, table)
    |> IO.inspect
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

    payload = Frame.pad_data(header_block_fragment, 2)

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
    data_frame = Frame.Data.new(1, "Upload", true) |> Frame.Data.serialize()
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
    data_frame = Frame.Data.new(1, "Upload", pad_length: 2, end_stream: true)
    :ssl.send(connection, data_frame)
    assert {:ok, %{header_block_fragment: hbf}} = Support.read_next(connection, 2_000)
    assert = [{":status", "201"}, {"content-length", "0"}] == HPack.decode(hbf, decode_table)
  end
end
