defmodule Ace.HTTP1.ServerTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, service} =
      Ace.HTTP.Service.start_link(
        {Raxx.Forwarder, %{target: self()}},
        port: 0,
        certfile: Support.test_certfile(),
        keyfile: Support.test_keyfile()
      )

    {:ok, port} = Ace.HTTP.Service.port(service)
    {:ok, %{port: port}}
  end

  # tests organised by
  # - service test
  # - connection tests
  # - request tests
  # - response tests

  ## Connection setup

  test "server can handle cleartext exchange" do
    {:ok, service} =
      Ace.HTTP.Service.start_link(
        {Raxx.Forwarder, %{target: self()}},
        port: 0,
        cleartext: true
      )

    {:ok, port} = Ace.HTTP.Service.port(service)

    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, _state}}, 1000
    assert request.scheme == :http

    response =
      Raxx.response(:ok)
      |> Raxx.set_header("x-test", "Value")
      |> Raxx.set_body("OK")

    GenServer.reply(from, response)

    assert_receive {:tcp, ^socket, response}, 1000

    assert response ==
             "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 2\r\nx-test: Value\r\n\r\nOK"
  end

  test "exits normal when client closes connection", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from = {worker, _ref}, {:headers, _request, state}}, 1000
    GenServer.reply(from, {[], state})
    # Worker receives request, but client closes connection before response is sent

    monitor = Process.monitor(worker)
    Process.sleep(500)
    :ok = :ssl.close(socket)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1000
  end

  # Connection level errors

  test "400 response for invalid start_line", %{port: port} do
    {:ok, connection} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ssl.send(connection, "rubbish\n")

    assert_receive {:ssl, ^connection, response}, 1000

    assert response ==
             "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:ssl_closed, ^connection}, 1000
  end

  test "400 response for invalid headers", %{port: port} do
    {:ok, connection} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ssl.send(connection, "GET / HTTP/1.1\r\na \r\n::\r\n")

    assert_receive {:ssl, ^connection, response}, 1000

    assert response ==
             "HTTP/1.1 400 Bad Request\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:ssl_closed, ^connection}, 1000
  end

  test "too long url ", %{port: port} do
    path =
      for(_i <- 1..3000, do: "a")
      |> Enum.join("")

    request = """
    GET /#{path} HTTP/1.1
    Host: www.raxx.com

    """

    {:ok, connection} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ssl.send(connection, request)

    assert_receive {:ssl, ^connection, response}, 1000

    assert response ==
             "HTTP/1.1 414 URI Too Long\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:ssl_closed, ^connection}, 1000
  end

  test "Client too slow to deliver request head", %{port: port} do
    unfinished_head = """
    GET / HTTP/1.1
    Host: www.raxx.com
    """

    {:ok, connection} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ssl.send(connection, unfinished_head)
    assert_receive {:ssl, ^connection, response}, 15000

    assert response ==
             "HTTP/1.1 408 Request Timeout\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  test "can connect with alpn preferences", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    x-test: Value

    """

    {:ok, socket} =
      :ssl.connect(
        {127, 0, 0, 1},
        port,
        mode: :binary,
        packet: :raw,
        active: false,
        alpn_advertised_protocols: ["http/1.1"]
      )

    assert {:ok, "http/1.1"} = :ssl.negotiated_protocol(socket)
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.scheme == :https
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.raw_path == "/foo/bar"
    assert request.query == "var=1"
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "renders 500 response if handler exits raises error" do
    {:ok, service} =
      Ace.HTTP.Service.start_link(
        {Raxx.Kaboom, %{target: self()}},
        port: 0,
        cleartext: true
      )

    {:ok, port} = Ace.HTTP.Service.port(service)

    http1_request = """
    GET /raise_error HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :gen_tcp.send(socket, http1_request)

    assert_receive {:tcp, ^socket, response}, 1000

    assert response ==
             "HTTP/1.1 500 Internal Server Error\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"
  end

  ## Request tests

  test "header information is added to request", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    x-test: Value

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.scheme == :https
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == "var=1"
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "Header keys in request are cast to lowercase", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    Host: example.com:1234
    X-test: Value

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.scheme == :https
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == "var=1"
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "handles duplicate headers", %{port: port} do
    http1_request = """
    GET /foo/bar HTTP/1.1
    host: example.com:1234
    Accept: text/plain
    Accept: text/html

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.scheme == :https
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert Enum.sort(request.headers) == [{"accept", "text/html"}, {"accept", "text/plain"}]
    assert request.body == false
  end
  
  test "handles request with split start-line ", %{port: port} do
    part_1 = "GET /foo/bar?var"

    part_2 = """
    =1 HTTP/1.1
    host: example.com:1234
    x-test: Value

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, part_1)
    :ok = Process.sleep(100)
    :ok = :ssl.send(socket, part_2)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.scheme == :https
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == "var=1"
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "handles request with split headers ", %{port: port} do
    part_1 = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    """

    part_2 = """
    x-test: Value

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, part_1)
    :ok = Process.sleep(100)
    :ok = :ssl.send(socket, part_2)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.scheme == :https
    assert request.authority == "example.com:1234"
    assert request.method == :GET
    assert request.mount == []
    assert request.path == ["foo", "bar"]
    assert request.query == "var=1"
    assert request.headers == [{"x-test", "Value"}]
    assert request.body == false
  end

  test "request with content-length 0 has no body", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    content-length: 0

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.body == false
  end

  test "request stream will end when all content has been read", %{port: port} do
    http1_request = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    content-length: 14

    Hello, World!
    And a bunch more content
    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.body == true

    assert_receive {:"$gen_call", from, {:data, data, state}}, 1000
    GenServer.reply(from, {[], state})

    assert "Hello, World!\n" == data

    assert_receive {:"$gen_call", from, {:tail, [], state}}, 1000
    GenServer.reply(from, {[], state})
  end

  test "application will be invoked as content is received", %{port: port} do
    request_head = """
    GET /foo/bar?var=1 HTTP/1.1
    host: example.com:1234
    content-length: 14

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, request_head)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    GenServer.reply(from, {[], state})

    assert request.body == true

    :ok = :ssl.send(socket, "Hello, ")
    Process.sleep(100)
    :ok = :ssl.send(socket, "World!\n")

    assert_receive {:"$gen_call", from, {:data, "Hello, ", state}}, 1000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:data, "World!\n", state}}, 1000
    GenServer.reply(from, {[], state})

    assert_receive {:"$gen_call", from, {:tail, [], state}}, 1000
    GenServer.reply(from, {[], state})
  end

  ## Response test

  test "server can send a complete response after receiving headers", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, _state}}, 1000

    response =
      Raxx.response(:ok)
      |> Raxx.set_header("content-length", "2")
      |> Raxx.set_header("x-test", "Value")
      |> Raxx.set_body("OK")

    GenServer.reply(from, response)

    assert_receive {:ssl, ^socket, response}, 1000

    assert response ==
             "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 2\r\nx-test: Value\r\n\r\nOK"
  end

  test "server can stream response with a predetermined size", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, state}}, 1000

    response =
      Raxx.response(:ok)
      |> Raxx.set_header("content-length", "15")
      |> Raxx.set_header("x-test", "Value")
      |> Raxx.set_body(true)

    GenServer.reply(from, {[response], state})

    assert_receive {:ssl, ^socket, response_head}, 1000

    assert response_head ==
             "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 15\r\nx-test: Value\r\n\r\n"

    {server, _ref} = from
    send(server, {[Raxx.data("Hello, ")], state})

    assert_receive {:ssl, ^socket, "Hello, "}, 1000
    send(server, {[Raxx.data("World!\r\n"), Raxx.tail()], state})

    assert_receive {:ssl, ^socket, "World!\r\n"}, 1000
  end

  test "content-length will be added for a complete response", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, _state}}, 1000

    response =
      Raxx.response(:ok)
      |> Raxx.set_header("x-test", "Value")
      |> Raxx.set_body("OK")

    GenServer.reply(from, response)

    assert_receive {:ssl, ^socket, response}, 1000

    assert response ==
             "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 2\r\nx-test: Value\r\n\r\nOK"
  end

  test "content-length will be added for a response with no body", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, _state}}, 1000

    response =
      Raxx.response(:ok)
      |> Raxx.set_header("x-test", "Value")
      |> Raxx.set_body(false)

    GenServer.reply(from, response)

    assert_receive {:ssl, ^socket, response}, 1000

    assert response ==
             "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 0\r\nx-test: Value\r\n\r\n"
  end

  ## Connection test

  test "connection is closed at clients request for HTTP 1.1 request", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com
    connection: close
    x-test: Value

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, _state}}, 1000
    GenServer.reply(from, Raxx.response(:no_content))

    assert request.headers == [{"x-test", "Value"}]
    assert_receive {:ssl, ^socket, response}, 1000
    assert response == "HTTP/1.1 204 No Content\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:ssl_closed, ^socket}, 1000
  end

  # DEBT implement HTTP/1.1 pipelining
  test "connection is closed at clients even for keep_alive request", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com
    connection: keep-alive
    x-test: Value

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, request, _state}}, 1000
    GenServer.reply(from, Raxx.response(:no_content))

    assert request.headers == [{"x-test", "Value"}]
    assert_receive {:ssl, ^socket, response}, 1000
    assert response == "HTTP/1.1 204 No Content\r\nconnection: close\r\ncontent-length: 0\r\n\r\n"

    assert_receive {:ssl_closed, ^socket}, 1000
  end

  ## Chunked transfer_encoding

  test "request can be sent in chunks", %{port: port} do
    request_head = """
    POST / HTTP/1.1
    host: example.com
    x-test: Value
    transfer-encoding: chunked

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, request_head)

    assert_receive {:"$gen_call", from, {:headers, request, state}}, 1000
    state = Map.put(state, :count, 1)
    GenServer.reply(from, {[], state})

    assert request.headers == [{"x-test", "Value"}]

    :ok = :ssl.send(socket, "D\r\nHello,")
    Process.sleep(100)
    :ok = :ssl.send(socket, " World!\r\nD")

    assert_receive {:"$gen_call", from, {:data, data, state}}, 1000
    assert 1 == state.count
    assert data == "Hello, World!"

    state = Map.put(state, :count, 2)
    GenServer.reply(from, {[], state})

    :ok = :ssl.send(socket, "\r\nHello, World!\r\n")

    assert_receive {:"$gen_call", from, {:data, data, state}}, 1000
    assert 2 == state.count
    assert data == "Hello, World!"

    state = Map.put(state, :count, 3)
    GenServer.reply(from, {[], state})

    :ok = :ssl.send(socket, "0\r\n\r\n")
    assert_receive {:"$gen_call", _from, {:tail, [], state}}, 1000
    assert 3 == state.count
  end

  test "there is request backpressure" do
    require Logger
    {:ok, service} =
      Ace.HTTP.Service.start_link(
        {Raxx.Forwarder, %{target: self()}},
        port: 0,
        cleartext: true
      )

    {:ok, port} = Ace.HTTP.Service.port(service)

    # oversize content-length so that we don't make assumptions about the tcp buffer size
    request_head = """
    POST / HTTP/1.1
    host: example.com
    content-length: 20000000

    """

    socket_opts = [:binary, {:send_timeout, 100}, {:send_timeout_close, false}]
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, socket_opts)
    Logger.info "request socket: #{inspect socket}"

    :ok = :gen_tcp.send(socket, request_head)

    assert_receive {:"$gen_call", from, {:headers, _request, state}}, 1000
    GenServer.reply(from, {[], state})
    one_kb_message = String.duplicate("bla ", div(1024, 4))

    Logger.info "filling up the buffer"
    sent_message_count = IO.inspect fill_up_buffer(socket, one_kb_message, 10_000)

    # if all 10_000 were sent, the buffer wasn't filled up
    assert sent_message_count < 10_000
    # sending fails, but it doesn't close the socket
    refute_receive {:tcp_closed, ^socket}

    IO.puts "draining the buffer"
    # drain all the messages sent so far
    processed_bytes = process_data()
    refute_receive {:"$gen_call", _from, {:data, _data, _state}}, 1000

    assert processed_bytes >= sent_message_count * 1024
    # a message can be partially sent, can't find it in the docs right now
    assert processed_bytes <= (sent_message_count + 1) * 1024

    :ok = :gen_tcp.send(socket, "last bit of the request")

    assert_receive {:"$gen_call", from, {:data, data, _state}}, 1000
    assert data == "last bit of the request"

    response = Raxx.response(:ok)|> Raxx.set_body("server's done!")
    GenServer.reply(from, response)

    assert_receive {:tcp, ^socket, "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-length: 14\r\n\r\nserver's done!"}
    assert_receive {:tcp_closed, ^socket}
  end

  defp fill_up_buffer(socket, message, max_count, sent_count \\ 0)

  defp fill_up_buffer(socket, message, max_count, sent_count) when max_count > sent_count do
    case :gen_tcp.send(socket, message) do
      :ok -> 
        fill_up_buffer(socket, message, max_count, sent_count + 1)
      {:error, :timeout} ->
        sent_count
    end
  end

  defp fill_up_buffer(_socket, _message, _max_count, sent_count) do
    sent_count
  end

  defp process_data(processed_so_far \\ 0) do
      receive do
        {:"$gen_call", from, {:data, data, state}} ->
          GenServer.reply(from, {[], state})
          process_data(processed_so_far + byte_size(data))
      after
        200 -> processed_so_far
      end
  end

  @tag :skip
  test "cannot receive content-length with transfer-encoding" do
  end

  @tag :skip
  test "cannot handle any other transfer-encoding" do
  end

  test "response without content length will be sent chunked", %{port: port} do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from, {:headers, _request, state}}, 1000

    response =
      Raxx.response(:ok)
      |> Raxx.set_header("x-test", "Value")
      |> Raxx.set_body(true)

    state = Map.put(state, :count, 1)

    GenServer.reply(from, {[response], state})

    assert_receive {:ssl, ^socket, headers}, 1000

    assert headers ==
             "HTTP/1.1 200 OK\r\nconnection: close\r\ntransfer-encoding: chunked\r\nx-test: Value\r\n\r\n"

    {server, _ref} = from
    send(server, {[Raxx.data("Hello, ")], state})

    assert_receive {:ssl, ^socket, part}, 1000
    assert part == "7\r\nHello, \r\n"

    send(server, {[Raxx.data("World!"), Raxx.tail()], state})

    assert_receive {:ssl, ^socket, part}, 1000
    assert part == "6\r\nWorld!\r\n0\r\n\r\n"

    assert_receive {:ssl_closed, ^socket}, 1000
  end

  # DEBT try sending empty fragment with end_stream false? should not end stream

  test "If a worker dies while sending a chunked response, its endpoint dies gracefully", %{
    port: port
  } do
    http1_request = """
    GET / HTTP/1.1
    host: example.com

    """

    {:ok, socket} = :ssl.connect({127, 0, 0, 1}, port, [:binary])
    :ok = :ssl.send(socket, http1_request)

    assert_receive {:"$gen_call", from = {worker, _ref}, {:headers, _request, state}}, 1000

    response =
      Raxx.response(:ok)
      |> Raxx.set_body(true)

    GenServer.reply(from, {[response], state})

    %{channel: %{endpoint: endpoint}, channel_monitor: _channel_monitor} = :sys.get_state(worker)
    endpoint_monitor = Process.monitor(endpoint)

    send(worker, {Raxx.Forwarder, :stop, :normal})

    assert_receive {:DOWN, ^endpoint_monitor, :process, ^endpoint, endpoint_exit_reason}, 1000
    assert endpoint_exit_reason == :normal
  end
end
