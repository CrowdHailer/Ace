defmodule Ace.HTTP2.FlowControlTest do
  # DEBT h2spec sends second byte on window update

  use ExUnit.Case

  @default_window_size 65_535
  @default_window_size_bits 65_535 * 8

  alias Ace.{
    HPack
  }
  alias Ace.HTTP2.{
    Frame
  }

  setup do
    {_server, port} = Support.start_server(self())
    connection = Support.open_connection(port)
    {:ok, %{client: connection}}
  end

  # Connection level

  test "data streaming is limited by connection flow control", %{client: connection} do
    :ssl.send(connection, Ace.HTTP2.Connection.preface())
    Support.send_frame(connection, Frame.Settings.new(initial_window_size: 3 * @default_window_size))
    assert {:ok, %Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Frame.Settings{ack: true}} == Support.read_next(connection)
    encode_context = HPack.new_context(4_096)

    headers_frame = headers_frame(1, Support.home_page_headers(), encode_context)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})
    assert_receive {stream, _headers}, 1_000
    headers = %{
      ":status" => "200",
      "content-length" => "13"
    }
    preface = %{
      headers: headers,
      end_stream: false
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
    data_size = @default_window_size_bits * 3
    data = %{
      data: <<0::size(data_size)>>,
      end_stream: true
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, data)
    assert {:ok, %Frame.Headers{}} = Support.read_next(connection, 2_000)
    assert {:ok, %Frame.Data{data: first_data, end_stream: false}} = Support.read_next(connection, 2_000)
    assert @default_window_size == :erlang.iolist_size(first_data)

    assert {:error, :timeout} = Support.read_next(connection, 2_000)

    Support.send_frame(connection, Frame.WindowUpdate.new(0, @default_window_size))
    assert {:ok, %Frame.Data{data: remaining_data, end_stream: false}} = Support.read_next(connection, 2_000)
    assert @default_window_size == :erlang.iolist_size(remaining_data)

    Support.send_frame(connection, Frame.WindowUpdate.new(0, @default_window_size))
    assert {:ok, %Frame.Data{data: remaining_data, end_stream: true}} = Support.read_next(connection, 2_000)
    assert @default_window_size == :erlang.iolist_size(remaining_data)
  end

  test "unused window update on connection is available for new streams", %{client: connection} do
    :ssl.send(connection, Ace.HTTP2.Connection.preface())
    Support.send_frame(connection, Frame.Settings.new(initial_window_size: 2 * @default_window_size))
    assert {:ok, %Frame.Settings{ack: false}} == Support.read_next(connection)
    assert {:ok, %Frame.Settings{ack: true}} == Support.read_next(connection)

    Support.send_frame(connection, Frame.WindowUpdate.new(0, @default_window_size))

    encode_context = HPack.new_context(4_096)

    headers_frame = headers_frame(1, Support.home_page_headers(), encode_context)
    Support.send_frame(connection, headers_frame)

    assert_receive {:"$gen_call", from, {:start_child, []}}, 1_000
    GenServer.reply(from, {:ok, self()})
    assert_receive {stream, _headers}, 1_000
    headers = %{
      ":status" => "200",
      "content-length" => "13"
    }
    preface = %{
      headers: headers,
      end_stream: false
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, preface)
    data_size = @default_window_size_bits + 8_000
    data = %{
      data: <<0::size(data_size)>>,
      end_stream: false
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, data)
    assert {:ok, %Frame.Headers{}} = Support.read_next(connection, 2_000)
    assert {:ok, %Frame.Data{data: first_data, end_stream: false}} = Support.read_next(connection, 2_000)
    assert @default_window_size + 1_000 == :erlang.iolist_size(first_data)

    data_size = 8_000
    data = %{
      data: <<0::size(data_size)>>,
      end_stream: true
    }
    Ace.HTTP2.StreamHandler.send_to_client(stream, data)
    assert {:ok, %Frame.Data{data: second_data, end_stream: true}} = Support.read_next(connection, 2_000)
    assert 1_000 == :erlang.iolist_size(second_data)
    # DEBT make sure that frames are sized appropriatly
  end

  # Stream level

  defp headers_frame(stream_id, headers, encode_context) when is_list(headers) do
    {:ok, {header_block, encode_context}} = HPack.encode(headers, encode_context)
    headers_frame = Frame.Headers.new(stream_id, header_block, true, true)
  end
end
