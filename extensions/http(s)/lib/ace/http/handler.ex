defmodule Ace.HTTP.Handler do
  use Ace.Application
  @moduledoc false
  @packet_timeout 10_000

  # states
  # {:request, :response}
  # {{:request_headers, partial}, :response}
  # {{:streamed_body, remaining}, :response || :steaming_body || :streaming_chunks}
  # {:chunked_body, :response || :steaming_body || :streaming_chunks}
  # {:complete, :response || :steaming_body || :streaming_chunks}

  defstruct [
    :conn_info,
    :config,
    :status # request, headers, streamed_body, chunked_body
  ]

  def handle_connect(conn_info, app) do
    state = %__MODULE__{
      conn_info: conn_info,
      config: app,
      status: {:request, :response}
    }
    {"", "", state}
  end

  defoverridable [handle_connect: 2]

  def handle_connect(info, config) do
    case super(info, config) do
      {outbound, unprocessed, state} ->
        case outbound do
          "" ->
            {:nosend, {unprocessed, state}}
          data ->
            {:send, data, {unprocessed, state}}
        end
    end
  end

  # # def process_headers(buffer, {:body, request = %{headers: headers}}) do
  # #   case :proplists.get_value("content-length", headers) do
  # #     content_length when content_length in [:undefined, 0] ->
  # #       {:ok, request, buffer}
  # #     raw ->
  # #       length = :erlang.binary_to_integer(raw)
  # #         true ->
  # #           case buffer do
  # #             <<body :: binary-size(length)>> <> rest ->
  # #               {:ok, %{request | body: body}, rest}
  # #             _ ->
  # #               {:more, {:body, request}, buffer}
  # #           end
  # #         false ->
  # #           reason = {:body_too_large, length}
  # #           # TODO exceptions to include what to do next
  # #           {:error, reason, :close}
  # #       end
  # #   end
  # # end
  # def handle_packet(packet, {app, partial, _buffer, conn_info}) do
  #   case process_headers(packet, partial) do
  #     {:more, partial, buffer} ->
  #       {:nosend, {app, partial, buffer, conn_info}, @packet_timeout}
  #     {:ok, request, buffer} ->
  #       {mod, state} = app
  #       case mod.handle_headers(request, state) do
  #         response = %Raxx.Response{} ->
  #           raw = Ace.HTTP1.serialize_response(response)
  #           {:send, raw, {app, {:start_line, conn_info}, buffer, conn_info}}
  #
  #         {actions, new_state} when is_list(actions) ->
  #           app = {mod, new_state}
  #           remaining = :proplists.get_value("content-length", request.headers, "0")
  #           {remaining, ""} = Integer.parse(remaining)
  #           if remaining == 0 do
  #             {:nosend, {app, {:start_line, conn_info}, buffer, conn_info}}
  #           else
  #             handle_packet(buffer, {:streaming, remaining, request, app, "", conn_info})
  #           end
  #         # basic_response = %{body: _, headers: _, status: _} ->
  #         #   raw = Ace.Response.serialize(basic_response)
  #         #   {:send, raw, {app, {:start_line, conn_info}, buffer, conn_info}}
  #       end
  #     {:error, reason, buffer} ->
  #       {mod, state} = app
  #       case mod.handle_error(reason) do
  #         binary_response when is_binary(binary_response) ->
  #           {:send, binary_response, {app, {:start_line, conn_info}, buffer, conn_info}}
  #         basic_response = %{body: _, headers: _, status: _} ->
  #           raw = Ace.Response.serialize(basic_response)
  #           {:send, raw, {app, {:start_line, conn_info}, buffer, conn_info}}
  #       end
  #   end
  # end

  def handle_data("", state) do
    {"", "", state}
  end

  def handle_data(packet, state = %{status: {:request, :response}}) do
    case :erlang.decode_packet(:http_bin, packet, []) do
      {:more, :undefined} ->
        {"", packet, state}
      {:ok, raw_request = {:http_request, _method, _http_uri, _version}, rest} ->
        partial = build_partial_request(raw_request, state.conn_info)
        new_status = {{:request_headers, partial}, :response}
        new_state = %{state | status: new_status}
        handle_data(rest, new_state)
    end
  end

  def handle_data(packet, state = %{status: {{:request_headers, partial}, :response}}) do
    case :erlang.decode_packet(:httph_bin, packet, []) do
      {:more, :undefined} ->
        {"", packet, state}
      {:ok, {:http_header, _, key, _, value}, rest} ->
        new_partial = add_header(partial, key, value)
        new_status = {{:request_headers, new_partial}, :response}
        new_state = %{state | status: new_status}
        handle_data(rest, new_state)
      {:ok, {:http_error, line}, rest} ->
        :todo
        # {:error, {:invalid_header_line, line}, rest}
      {:ok, :http_eoh, rest} ->
        {request, new_status} = cond do
          false ->
            # Need to check if encoding is chunked
            :todo
          (remaining = content_length(partial) || 0) > 0 ->
            {Raxx.set_body(partial, true), {{:body, remaining}, :response}}
          (remaining = content_length(partial) || 0) == 0 ->
            {Raxx.set_body(partial, false), {:complete, :response}}
        end
        {actions, app} = forward_request(request, state.config)
        {outbound, newer_status} = Enum.reduce(actions, {[], new_status}, &process_response/2)
        newer_state = %{state | status: newer_status, config: app}
        case newer_status do
          {_, :complete} ->
            {outbound, :stopped, newer_state}
          _other ->
            {outbound2, rest2, newer_state2} = handle_data(rest, newer_state)
            {outbound ++ outbound2, rest2, newer_state}
        end

    end
  end

  def process_response(response = %Raxx.Response{}, {acc, {receiving, :response}}) do
    if Raxx.complete?(response) do
      {acc ++ [Ace.HTTP1.serialize_response(response)], {receiving, :complete}}
    else
      remaining = content_length(response)
      {acc ++ [Ace.HTTP1.serialize_response(response)], {receiving, {:body, remaining}}}
    end
  end
  def process_response(%Raxx.Fragment{data: data, end_stream: false}, {acc, {receiving, {:body, remaining}}}) when byte_size(data) < remaining do
    {acc ++ [data], {receiving, {:body, remaining - :erlang.iolist_size(data)}}}
  end
  def process_response(%Raxx.Fragment{data: data, end_stream: true}, {acc, {receiving, {:body, remaining}}}) when byte_size(data) == remaining do
    {acc ++ [data], {receiving, :complete}}
  end

  # TODO broken data
  def handle_data(packet, state = %{status: {{:body, remaining}, :response}}) when byte_size(packet) >= remaining do
    <<data::binary-size(remaining), rest::binary>> = packet
    forward_fragment(data, true, state.config)
    new_status = {:complete, :response}
    new_state = %{state | status: new_status}
    {"", rest, new_state}
  end

  def handle_packet("", x) do
    {:nosend, x}
  end
  def handle_packet(data, {buffer, state}) do
    case handle_data(buffer <> data, state) do
      {outbound, unprocessed, state} ->
        case outbound do
          "" ->
            {:nosend, {unprocessed, state}}
          iodata when is_binary(iodata) or is_list(iodata) ->
            {:send, iodata, {unprocessed, state}}
        end
    end
  end

  def handle_info(message, {buffer, state}) do
    {mod, app_state} = state.config
    {actions, app_state} = mod.handle_info(message, app_state)
    |> normalise_reaction(mod)
    {outbound, newer_status} = Enum.reduce(actions, {[], state.status}, &process_response/2)
    newer_state = %{state | status: newer_status}
    case newer_status do
      {_, :complete} ->
        {outbound, :stopped, newer_state}
      _other ->
        {outbound, buffer, newer_state}
    end
    |> case do
      {outbound, unprocessed, state} ->
        case outbound do
          "" ->
            {:nosend, {unprocessed, state}}
          iodata when is_binary(iodata) or is_list(iodata) ->
            {:send, iodata, {unprocessed, state}}
        end
    end
  end

  def forward_request(request, {mod, state}) do
    mod.handle_headers(request, state)
    |> normalise_reaction(mod)
  end

  def forward_fragment(data, end_stream, {mod, state}) do
    mod.handle_fragment(data, state)
    if end_stream do
      mod.handle_trailers([], state)
    end
  end

  def normalise_reaction(response = %Raxx.Response{}, mod) do
    if Raxx.complete?(response) do
      normalise_reaction({[response], :stop}, mod)
    else
      raise "Do not send like this unless complete response"
    end
  end
  def normalise_reaction({actions, app_state}, mod) when is_list(actions) do
    {actions, {mod, app_state}}
  end

  def handle_disconnect(_reason, _) do
    :ok
  end

  def build_partial_request({:http_request, method, http_uri, _version}, conn_info) do
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
    scheme = case conn_info.transport do
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

  defp content_length(request = %{headers: headers}) do
    case :proplists.get_value("content-length", headers) do
      :undefined ->
        nil
      binary ->
        {content_length, ""} = Integer.parse(binary)
      content_length
    end
  end

  def add_header(request = %{headers: headers}, :Host, location) do
    %{request | headers: headers, authority: location}
  end
  def add_header(request = %{headers: headers}, key, value) do
    key = String.downcase("#{key}")
    headers = headers ++ [{key, value}]
    %{request | headers: headers}
  end

end
