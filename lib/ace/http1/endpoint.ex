defmodule Ace.HTTP1.Endpoint do
  @moduledoc """
  """

  @packet_timeout 10_000
  @max_line_length 2048

  @bad_request """
  HTTP/1.1 400 Bad Request
  connection: close
  content-length: 0

  """ |> String.replace("\n", "\r\n")

  @start_line_too_long """
  HTTP/1.1 414 URI Too Long
  connection: close
  content-length: 0

  """ |> String.replace("\n", "\r\n")

  @request_timeout """
  HTTP/1.1 408 Request Timeout
  connection: close
  content-length: 0

  """ |> String.replace("\n", "\r\n")

  alias Raxx.{
    Response,
    Fragment
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

  def handle_info({:ssl, _socket, packet}, {buffer, state}) do
    case receive_data(buffer <> packet, state) do
      {:ok, {rest, state}} ->
        case state.status do
          {:complete, _} ->
            :ok = :ssl.setopts(state.socket, active: :once)
            {:noreply, {rest, state}}
          {_incomplete, _} ->
            :ok = :ssl.setopts(state.socket, active: :once)
            {:noreply, {rest, state}, @packet_timeout}
        end
      {:error, {:invalid_start_line, _line}} ->
        :ssl.send(state.socket, @bad_request)
        {:stop, :normal, state}
      {:error, {:invalid_header_line, _line}} ->
        :ssl.send(state.socket, @bad_request)
        {:stop, :normal, state}
      {:error, :start_line_too_long} ->
        :ssl.send(state.socket, @start_line_too_long)
        {:stop, :normal, state}
    end
  end
  def handle_info({channel = {:http1, _, _}, part}, {buffer, state}) do
    ^channel = state.channel
    {:ok, {outbound, state}} = send_part(part, state)
    :ssl.send(state.socket, outbound)
    case state.status do
      {_, :complete} ->
        {:stop, :normal, {buffer, state}}
      {_, _incomplete} ->
        {:noreply, {buffer, state}}
    end
  end
  def handle_info(:timeout, {_buffer, state}) do
    :ssl.send(state.socket, @request_timeout)
    {:stop, :normal, state}
  end

  defp receive_data("", state) do
    {:ok, {"", state}}
  end
  defp receive_data(data, state = %{status: {:request, :response}}) do
    case :erlang.decode_packet(:http_bin, data, [line_length: @max_line_length]) do
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
        {request, new_status} = cond do
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
  defp receive_data(packet, state = %{status: {{:body, remaining}, :response}}) when byte_size(packet) >= remaining do
    <<data::binary-size(remaining), rest::binary>> = packet
    fragment = Raxx.fragment(data, false)
    send(state.worker, {state.channel, fragment})
    send(state.worker, {state.channel, Raxx.trailer([])})
    new_status = {:complete, :response}
    new_state = %{state | status: new_status}
    {:ok, {rest, new_state}}
  end
  defp receive_data(packet, state = %{status: {{:body, remaining}, :response}}) when byte_size(packet) < remaining do
    fragment = Raxx.fragment(packet, false)
    new_status = {{:body, remaining - byte_size(packet)}, :response}
    new_state = %{state | status: new_status}

    send(state.worker, {state.channel, fragment})

    {:ok, {"", new_state}}
  end
  defp receive_data(packet, state = %{status: {:chunked_body, :response}}) do
    {chunk, rest} = HTTP1.pop_chunk(packet)
    case chunk do
      nil ->
        {:ok, {rest, state}}
      "" ->
        send(state.worker, {state.channel, Raxx.trailer([])})
        {:ok, {rest, state}}
      chunk ->
        fragment = Raxx.fragment(chunk, false)
        send(state.worker, {state.channel, fragment})
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
  defp send_part(response = %Response{body: body}, state = %{status: {up, :response}}) when is_binary(body) do
    case content_length(response) do
      nil ->
        content_length = :erlang.iolist_size(body) |> to_string
        headers = [{"connection", "close"}, {"content-length", content_length} | response.headers]
        new_status = {up, :complete}
        new_state = %{state | status: new_status}
        new_state # Not used
        outbound = HTTP1.serialize_response(response.status, headers, response.body)
        {:ok, {outbound, new_state}}
      _content_length ->
        headers = [{"connection", "close"} | response.headers]
        new_status = {up, :complete}
        new_state = %{state | status: new_status}
        new_state # Not used
        outbound = HTTP1.serialize_response(response.status, headers, response.body)
        {:ok, {outbound, new_state}}
    end
  end
  defp send_part(fragment = %Fragment{}, state = %{status: {up, {:body, remaining}}}) do
    remaining = remaining - :erlang.iolist_size(fragment.data)
    new_status = {up, {:body, remaining}}
    new_state = %{state | status: new_status}
    {:ok, {[fragment.data], new_state}}
  end
  defp send_part(fragment = %Fragment{end_stream: false}, state = %{status: {_up, :chunked_body}}) do
    chunk = HTTP1.serialize_chunk(fragment.data)
    {:ok, {[chunk], state}}
  end
  defp send_part(fragment = %Fragment{end_stream: true}, state = %{status: {up, :chunked_body}}) do
    chunk = HTTP1.serialize_chunk(fragment.data)
    new_status = {up, :complete}
    new_state = %{state | status: new_status}
    {:ok, {[chunk, HTTP1.serialize_chunk("")], new_state}}
  end

  defp build_partial_request({:http_request, method, http_uri, _version}, transport) do
    path_string = case http_uri do
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
    scheme = case transport do
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
