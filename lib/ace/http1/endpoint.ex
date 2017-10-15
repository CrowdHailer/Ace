defmodule Ace.HTTP1.Endpoint do
  @moduledoc false

  @packet_timeout 10000
  @max_line_length 2048

  @bad_request """
               HTTP/1.1 400 Bad Request
               connection: close
               content-length: 0

               """
               |> String.replace("\n", "\r\n")

  @start_line_too_long """
                       HTTP/1.1 414 URI Too Long
                       connection: close
                       content-length: 0

                       """
                       |> String.replace("\n", "\r\n")

  @request_timeout """
                   HTTP/1.1 408 Request Timeout
                   connection: close
                   content-length: 0

                   """
                   |> String.replace("\n", "\r\n")

  alias Raxx.{
    Response,
    Data,
    Tail
  }
  alias Ace.HTTP1

  use GenServer

  defstruct [
    :status,
    :socket,
    :worker,
    :channel,
    :keep_alive
  ]

  def handle_info({transport, _socket, packet}, {buffer, state}) when transport in [:tcp, :ssl] do
    case receive_data(buffer <> packet, state) do
      {:ok, {rest, state}} ->
        case state.status do
          {:complete, _} ->
            :ok = set_active(state.socket)
            {:noreply, {rest, state}}

          {_incomplete, _} ->
            :ok = set_active(state.socket)
            {:noreply, {rest, state}, @packet_timeout}
        end

      {:error, {:invalid_start_line, _line}} ->
        send_packet(state.socket, @bad_request)
        {:stop, :normal, state}

      {:error, {:invalid_header_line, _line}} ->
        send_packet(state.socket, @bad_request)
        {:stop, :normal, state}

      {:error, :start_line_too_long} ->
        send_packet(state.socket, @start_line_too_long)
        {:stop, :normal, state}
    end
  end

  def handle_info({channel = {:http1, _, _}, parts}, {buffer, state}) do
    ^channel = state.channel
    {outbound, state} = Enum.reduce(parts, {"", state}, fn(part, {buffer, state}) ->
    {:ok, {outbound, next_state}} = send_part(part, state)
    {[buffer, outbound], next_state}
    end)
    send_packet(state.socket, outbound)

    case state.status do
      {_, :complete} ->
        {:stop, :normal, {buffer, state}}

      {_, _incomplete} ->
        {:noreply, {buffer, state}}
    end
  end

  def handle_info(:timeout, {_buffer, state}) do
    send_packet(state.socket, @request_timeout)
    {:stop, :normal, state}
  end

  def handle_info({transport, _socket}, {buffer, state})
      when transport in [:tcp_closed, :ssl_closed] do
    # Sending an exit :normal signal will do nothing. maybe the correct behaviour is to send a message
    # Or probably to have a two way monitor
    Process.exit(state.worker, :shutdown)
    {:stop, :normal, {buffer, state}}
  end

  defp send_packet({:tcp, socket}, packet) do
    :gen_tcp.send(socket, packet)
  end

  defp send_packet(socket, packet) do
    :ssl.send(socket, packet)
  end

  defp set_active({:tcp, socket}) do
    :inet.setopts(socket, active: :once)
  end

  defp set_active(socket) do
    :ssl.setopts(socket, active: :once)
  end

  defp receive_data("", state) do
    {:ok, {"", state}}
  end

  defp receive_data(data, state = %{status: {:request, :response}}) do
    case :erlang.decode_packet(:http_bin, data, line_length: @max_line_length) do
      {:more, :undefined} ->
        {:ok, {data, state}}

      {:ok, {:http_error, line}, _rest} ->
        {:error, {:invalid_start_line, line}}

      {:error, :invalid} ->
        {:error, :start_line_too_long}

      {:ok, raw_request = {:http_request, _method, _http_uri, _version}, rest} ->
        partial = build_partial_request(raw_request, :tls)
        new_status = {{:request_headers, partial}, :response}
        new_state = %{state | status: new_status}
        receive_data(rest, new_state)
    end
  end

  defp receive_data(data, state = %{status: {{:request_headers, partial}, :response}}) do
    case :erlang.decode_packet(:httph_bin, data, []) do
      {:more, :undefined} ->
        {:ok, {data, state}}

      {:ok, {:http_header, _, key, _, value}, rest} ->
        case key do
          :Connection ->
            if value != "close" do
              IO.puts("received 'connection: #{value}', Ace will always close connection")
            end

            new_state = %{state | keep_alive: false}
            receive_data(rest, new_state)

          _other ->
            new_partial = add_header(partial, key, value)
            new_status = {{:request_headers, new_partial}, :response}
            new_state = %{state | status: new_status}
            receive_data(rest, new_state)
        end

      {:ok, {:http_error, line}, rest} ->
        {:error, {:invalid_header_line, line}}

      {:ok, :http_eoh, rest} ->
        {transfer_encoding, partial} = pop_transfer_encoding(partial)

        {request, new_status} =
          cond do
            transfer_encoding == "chunked" ->
              {Raxx.set_body(partial, true), {:chunked_body, :response}}

            transfer_encoding != nil ->
              raise "Transfer encoding '#{transfer_encoding}' not supported by Ace.HTTP1 (beta)"

            content_length(partial) in [0, nil] ->
              {Raxx.set_body(partial, false), {:complete, :response}}

            (remaining = content_length(partial)) > 0 ->
              {Raxx.set_body(partial, true), {{:body, remaining}, :response}}
          end

        send(state.worker, {state.channel, request})
        new_state = %{state | status: new_status}
        receive_data(rest, new_state)
    end
  end

  defp receive_data(packet, state = %{status: {{:body, remaining}, :response}})
       when byte_size(packet) >= remaining do
    <<data::binary-size(remaining), rest::binary>> = packet
    data = Raxx.data(data)
    send(state.worker, {state.channel, data})
    send(state.worker, {state.channel, Raxx.tail()})
    new_status = {:complete, :response}
    new_state = %{state | status: new_status}
    {:ok, {rest, new_state}}
  end

  defp receive_data(packet, state = %{status: {{:body, remaining}, :response}})
       when byte_size(packet) < remaining do
    data = Raxx.data(packet)
    new_status = {{:body, remaining - byte_size(packet)}, :response}
    new_state = %{state | status: new_status}

    send(state.worker, {state.channel, data})

    {:ok, {"", new_state}}
  end

  defp receive_data(packet, state = %{status: {:chunked_body, :response}}) do
    {chunk, rest} = HTTP1.pop_chunk(packet)

    case chunk do
      nil ->
        {:ok, {rest, state}}

      "" ->
        send(state.worker, {state.channel, Raxx.tail([])})
        {:ok, {rest, state}}

      chunk ->
        data = Raxx.data(chunk)
        send(state.worker, {state.channel, data})
        {:ok, {rest, state}}
    end
  end

  defp send_part(response = %Response{body: true}, state = %{status: {up, :response}}) do
    case content_length(response) do
      nil ->
        headers = [{"connection", "close"}, {"transfer-encoding", "chunked"} | response.headers]
        new_status = {up, :chunked_body}
        new_state = %{state | status: new_status}
        outbound = HTTP1.serialize_response(response.status, headers, "")
        {:ok, {outbound, new_state}}

      content_length when content_length > 0 ->
        headers = [{"connection", "close"} | response.headers]
        new_status = {up, {:body, content_length}}
        new_state = %{state | status: new_status}
        outbound = HTTP1.serialize_response(response.status, headers, "")
        {:ok, {outbound, new_state}}
    end
  end

  defp send_part(response = %Response{body: false}, state = %{status: {up, :response}}) do
    case content_length(response) do
      nil ->
        headers = [{"connection", "close"}, {"content-length", "0"} | response.headers]
        new_status = {up, :complete}
        new_state = %{state | status: new_status}
        outbound = HTTP1.serialize_response(response.status, headers, "")
        {:ok, {outbound, new_state}}
    end
  end

  defp send_part(response = %Response{body: body}, state = %{status: {up, :response}})
       when is_binary(body) do
    case content_length(response) do
      nil ->
        content_length = :erlang.iolist_size(body) |> to_string
        headers = [{"connection", "close"}, {"content-length", content_length} | response.headers]
        new_status = {up, :complete}
        new_state = %{state | status: new_status}
        # Not used
        new_state
        outbound = HTTP1.serialize_response(response.status, headers, response.body)
        {:ok, {outbound, new_state}}

      _content_length ->
        headers = [{"connection", "close"} | response.headers]
        new_status = {up, :complete}
        new_state = %{state | status: new_status}
        # Not used
        new_state
        outbound = HTTP1.serialize_response(response.status, headers, response.body)
        {:ok, {outbound, new_state}}
    end
  end

  defp send_part(data = %Data{}, state = %{status: {up, {:body, remaining}}}) do
    remaining = remaining - :erlang.iolist_size(data.data)
    new_status = {up, {:body, remaining}}
    new_state = %{state | status: new_status}
    {:ok, {[data.data], new_state}}
  end

  defp send_part(%Tail{headers: []}, state = %{status: {up, {:body, 0}}}) do
    new_status = {up, :complete}
    new_state = %{state | status: new_status}
    {:ok, {[], new_state}}
  end

  defp send_part(%Data{data: data}, state = %{status: {_up, :chunked_body}}) do
    chunk = HTTP1.serialize_chunk(data)
    {:ok, {[chunk], state}}
  end
  defp send_part(%Tail{headers: []}, state = %{status: {up, :chunked_body}}) do
    chunk = HTTP1.serialize_chunk("")
    new_status = {up, :complete}
    new_state = %{state | status: new_status}

    {:ok, {[chunk], new_state}}
  end

  defp build_partial_request({:http_request, method, http_uri, _version}, transport) do
    path_string =
      case http_uri do
        {:abs_path, path_string} ->
          path_string

        {:absoluteURI, _scheme, _host, _port, path_string} ->
          # Throw away the rest of the absolute URI since we are not proxying
          path_string
      end

    %{path: path, query: query_string} = URI.parse(path_string)
    # DEBT in case of path '//' then parsing returns path of nil.
    # e.g. localhost:8080//
    path = path || "/"
    {:ok, query} = URI2.Query.decode(query_string || "")
    path = Raxx.split_path(path)

    scheme =
      case transport do
        :tcp ->
          :http

        :tls ->
          :https
      end

    %Raxx.Request{
      scheme: scheme,
      method: method,
      path: path,
      query: query,
      headers: [],
      body: false
    }
  end

  defp pop_transfer_encoding(request = %{headers: headers}) do
    case :proplists.get_value("transfer-encoding", headers) do
      :undefined ->
        {nil, request}

      binary ->
        headers = :proplists.delete("transfer-encoding", headers)
        {binary, %{request | headers: headers}}
    end
  end

  defp content_length(%{headers: headers}) do
    case :proplists.get_value("content-length", headers) do
      :undefined ->
        nil

      binary ->
        {content_length, ""} = Integer.parse(binary)
        content_length
    end
  end

  defp add_header(request = %{headers: headers}, :Host, location) do
    %{request | headers: headers, authority: location}
  end

  defp add_header(request = %{headers: headers}, key, value) do
    key = String.downcase("#{key}")
    headers = headers ++ [{key, value}]
    %{request | headers: headers}
  end
end
