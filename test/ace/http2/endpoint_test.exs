defmodule Ace.HTTP2.EndpointTest do
  use ExUnit.Case, async: true

  alias Ace.HTTP2.{Endpoint, Frame}

  describe "Connecting to a server" do
    setup %{} do
      socket = :socket

      {:ok, worker_supervisor} =
        Supervisor.start_link(
          [{Ace.HTTP.Worker, {Raxx.Forwarder, %{self: self()}}}],
          strategy: :simple_one_for_one,
          max_restarts: 5000
        )

      endpoint = Endpoint.server(socket, worker_supervisor)
      {:ok, %{endpoint: endpoint}}
    end

    test "receives ack for preface settings frame", %{endpoint: endpoint} do
      packet = serialize([:preamble, Frame.Settings.new()])
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, packet)

      assert [{endpoint.socket, Frame.Settings.ack()}] == messages
    end

    test "preface can be split in client preamble", %{endpoint: endpoint} do
      # NOTE length of client preamble is 24 octets
      {p1, p2} = serialize([:preamble, Frame.Settings.new()]) |> String.split_at(15)

      {:ok, {[], endpoint}} = Endpoint.receive_packet(endpoint, p1)
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, p2)

      assert [{endpoint.socket, Frame.Settings.ack()}] == messages
    end

    test "preface can be split in first frame", %{endpoint: endpoint} do
      # NOTE length of client preamble is 24 octets
      {p1, p2} = serialize([:preamble, Frame.Settings.new()]) |> String.split_at(28)

      {:ok, {[], endpoint}} = Endpoint.receive_packet(endpoint, p1)
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, p2)

      assert [{endpoint.socket, Frame.Settings.ack()}] == messages
    end

    test "fails without client preamble", %{endpoint: endpoint} do
      packet = serialize([Frame.Settings.new(), :preamble])
      {:error, {:protocol_error, _debug}} = Endpoint.receive_packet(endpoint, packet)
    end

    test "fails without client settings frame", %{endpoint: endpoint} do
      packet = serialize([:preamble, Frame.Ping.new("12345678")])
      {:error, {:protocol_error, _debug}} = Endpoint.receive_packet(endpoint, packet)
    end

    test "fails if server settings acked before sending client settings", %{endpoint: endpoint} do
      packet = serialize([:preamble, Frame.Settings.ack()])
      {:error, {:protocol_error, _debug}} = Endpoint.receive_packet(endpoint, packet)
    end
  end

  describe "Initializing a stream for received headers" do
    setup %{} do
      socket = :socket

      {:ok, worker_supervisor} =
        Supervisor.start_link(
          [{Ace.HTTP.Worker, {Raxx.Forwarder, %{self: self()}}}],
          strategy: :simple_one_for_one,
          max_restarts: 5000
        )

      endpoint = Endpoint.server(socket, worker_supervisor)
      packet = serialize([:preamble, Frame.Settings.new()])
      {:ok, {_messages, endpoint}} = Endpoint.receive_packet(endpoint, packet)
      {:ok, %{endpoint: endpoint}}
    end

    test "sends request to worker process", %{endpoint: endpoint} do
      client_encode_context = Ace.HPack.new_context(1000)
      headers = Support.home_page_headers()
      {:ok, {header_block, _}} = Ace.HPack.encode(headers, client_encode_context)

      packet = serialize([Frame.Headers.new(1, header_block, true, true)])
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, packet)

      assert [{_pid, request = %Raxx.Request{}}] = messages

      # TODO send a header that ends up in headers
      assert :https == request.scheme
      assert "example.com" == request.authority
      assert :GET == request.method
      assert [] == request.path
      assert %{} == request.query
      assert [] == request.headers
      assert false == request.body
    end

    # {:ok, {header_block2, encode_context}} = Ace.HPack.encode(headers, encode_context)
    #
    # # Ace.HPack.decode(header_block2, Ace.HPack.new_context(1000))
    # # |> IO.inspect
    test "can be split over continuation frames", %{endpoint: endpoint} do
      # TODO
    end

    test "can specify following body", %{endpoint: endpoint} do
      client_encode_context = Ace.HPack.new_context(1000)
      headers = Support.home_page_headers()
      {:ok, {header_block, _}} = Ace.HPack.encode(headers, client_encode_context)

      packet = serialize([Frame.Headers.new(1, header_block, true, false)])
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, packet)

      assert [{_pid, request = %Raxx.Request{}}] = messages

      assert true == request.body
    end

    test "can send packed headers on subsequent request", %{endpoint: endpoint} do
      encode_context = Ace.HPack.new_context(1000)
      headers = Support.home_page_headers()
      {:ok, {header_block1, encode_context}} = Ace.HPack.encode(headers, encode_context)
      {:ok, {header_block2, _encode_context}} = Ace.HPack.encode(headers, encode_context)

      assert header_block1 != header_block2

      packet = serialize([Frame.Headers.new(1, header_block1, true, true), Frame.Headers.new(3, header_block2, true, true)])
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, packet)

      assert [{_pid1, request}, {_pid2, request}] = messages
    end

    # This might be later on in a continuation section

    # section 5.1.1
    #  An endpoint that
    #  receives an unexpected stream identifier MUST respond with a
    #  connection error (Section 5.4.1) of type PROTOCOL_ERROR.
    test "fails if stream_id is for server", %{endpoint: endpoint} do
      encode_context = Ace.HPack.new_context(1000)
      headers = Support.home_page_headers()
      {:ok, {header_block, encode_context}} = Ace.HPack.encode(headers, encode_context)

      packet = serialize([Frame.Headers.new(2, header_block, true, true)])
      {:error, {:protocol_error, _debug}} = Endpoint.receive_packet(endpoint, packet)
    end

    test "fails if on an already started stream", %{endpoint: endpoint} do

    end

    test "fails if sending response", %{endpoint: endpoint} do

    end

    test "fails if stream is already closed", %{endpoint: endpoint} do
      encode_context = Ace.HPack.new_context(1000)
      headers = Support.home_page_headers()
      {:ok, {header_block1, encode_context}} = Ace.HPack.encode(headers, encode_context)
      {:ok, {header_block2, _encode_context}} = Ace.HPack.encode(headers, encode_context)

      packet = serialize([Frame.Headers.new(1, header_block1, true, true), Frame.Headers.new(1, header_block2, true, true)])
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, packet)

      assert {:error, {:protocol_error, 55}} = messages
    end

    test "fails if sending push_promise", %{endpoint: endpoint} do

    end
  end

  describe "Data sent from client" do
    # start stream 1 closed
    # stream 3 active
    # cannot receive more than the length described
    # cannot send on closed
    # cannot send on idle
  end

  describe "receiving stream trailers" do

  end

  describe "Stream worker terminating" do
    test "will send reset frame" do
      # normal -> error cancelled
      # any_other -> server error
    end

    test "will have no effect on already closed stream" do

    end
  end

  describe "Server can exchange pings" do
    setup %{} do
      socket = :socket

      {:ok, worker_supervisor} =
        Supervisor.start_link(
          [{Ace.HTTP.Worker, {Raxx.Forwarder, %{self: self()}}}],
          strategy: :simple_one_for_one,
          max_restarts: 5000
        )

      endpoint = Endpoint.server(socket, worker_supervisor)
      packet = serialize([:preamble, Frame.Settings.new()])
      {:ok, {_messages, endpoint}} = Endpoint.receive_packet(endpoint, packet)
      {:ok, %{endpoint: endpoint}}
    end

    test "will acknowledge a valid pings", %{endpoint: endpoint} do
      packet = serialize([Frame.Ping.new("12345678")])
      {:ok, {messages, _endpoint}} = Endpoint.receive_packet(endpoint, packet)

      assert [%Frame.Ping{ack: true, identifier: "12345678"}]
    end

    test "will await ping sent to client for caller" do
      # TODO how would you even ping from the server.
      # I guess can work out endpoint pid from exchange reference
    end

    test "connection error for invalid ping" do

    end
  end

  describe "settings for server" do
  end


  # If connection error is going to kill the connection, then no point forwarding messages.
  # Therefore send all at the same time

  # If several streams can be started by one packet then can't have a next worker waiting
  # can return {:worker, head}


  defp serialize(frames) do
    Enum.map(frames, fn
      :preamble ->
        Ace.HTTP2.Connection.preface()

      frame ->
        Frame.serialize(frame)
    end)
    |> :erlang.iolist_to_binary()
  end
end
