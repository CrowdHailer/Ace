defmodule Ace.HTTP.Handler do
  use Ace.Application
  @moduledoc false
  @max_line_buffer 2048
  @packet_timeout 10_000
  @max_body_size 10_000_000 # 10MB

  def handle_connect(conn_info, app) do
    partial = {:start_line, conn_info}
    buffer = ""
    {:nosend, {app, partial, buffer, conn_info}}
  end

  def handle_packet(packet, {app, partial, buffer, conn_info}) do
    case process_buffer(buffer <> packet, partial) do
      {:more, partial, buffer} ->
        {:nosend, {app, partial, buffer, conn_info}, @packet_timeout}
      {:ok, request, buffer} ->
        {mod, state} = app
        case mod.handle_request(request, state) do
          chunked_response = %Ace.ChunkedResponse{} ->
            to_write = Ace.Response.serialize(chunked_response)
            app = chunked_response.app || app
            {:send, to_write, {:streaming, app}}
          basic_response = %{body: _, headers: _, status: _} ->
            raw = Ace.Response.serialize(basic_response)
            {:send, raw, {app, {:start_line, conn_info}, buffer, conn_info}}
        end
      {:error, reason, buffer} ->
        {mod, state} = app
        case mod.handle_error(reason) do
          binary_response when is_binary(binary_response) ->
            {:send, binary_response, {app, {:start_line, conn_info}, buffer, conn_info}}
          basic_response = %{body: _, headers: _, status: _} ->
            raw = Ace.Response.serialize(basic_response)
            {:send, raw, {app, {:start_line, conn_info}, buffer, conn_info}}
        end
    end
  end

  def handle_info(:timeout, state = {app = {mod, _config}, partial, _buffer, conn_info}) do
    error = case partial do
      {:body, _} ->
        :body_timeout
    end
    case mod.handle_error(error) do
      binary_response when is_binary(binary_response) ->
        {:send, binary_response, state}
      basic_response = %{body: _, headers: _, status: _} ->
        raw = Ace.Response.serialize(basic_response)
        {:send, raw, state}
    end
  end
  def handle_info(message, {:streaming, {mod, state}}) do
    chunks = mod.handle_info(message, state)
    case chunks do
      [] ->
        {:nosend, {:streaming, {mod, state}}}
      data when is_list(data) ->
        chunks = Enum.map(data, &Ace.Chunk.serialize/1)
        {:send, chunks, {:streaming, {mod, state}}}
    end
  end

  def handle_disconnect(_reason, _) do
    :ok
  end

  def process_buffer(buffer, {:start_line, conn_info}) when byte_size(buffer) < @max_line_buffer do
    case :erlang.decode_packet(:http_bin, buffer, []) do
      {:more, :undefined} ->
        {:more, {:start_line, conn_info}, buffer}
      {:ok, {:http_request, method, http_uri, _version}, rest} ->
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
        path = Raxx.Request.split_path(path)
        scheme = case conn_info.transport do
          :tcp -> "http"
          :ssl -> "https" # DEBT remove
          :tls -> "https"
        end
        peer = conn_info.peer
        request = %Raxx.Request{
          scheme: scheme,
          peer: peer,
          method: method,
          path: path,
          query: query,
          headers: []
        }
        process_buffer(rest, {:headers, request})
      {:ok, {:http_error, line}, rest} ->
        {:error, {:invalid_request_line, line}, rest}
    end
  end
  def process_buffer(buffer, {:start_line, conn_info}) when byte_size(buffer) >= 2048 do
    {:error, :start_line_too_long, :no_recover}
  end
  def process_buffer(buffer, {:headers, request}) do
    case :erlang.decode_packet(:httph_bin, buffer, []) do
      {:more, :undefined} ->
        {:more, {:headers, request}, buffer}
      # Key values is binary for unknown headers, atom and capitalised for known.
      {:ok, {:http_header, _, key, _, value}, rest} ->
        process_buffer(rest, {:headers, add_header(request, key, value)})
      {:ok, {:http_error, line}, rest} ->
        {:error, {:invalid_header_line, line}, rest}
      {:ok, :http_eoh, rest} ->
        process_buffer(rest, {:body, request})
    end
  end
  def process_buffer(buffer, {:body, request = %{headers: headers}}) do
    case :proplists.get_value("content-length", headers) do
      :undefined ->
        {:ok, request, buffer}
      raw ->
        length = :erlang.binary_to_integer(raw)
        case length < @max_body_size do
          true ->
            case buffer do
              <<body :: binary-size(length)>> <> rest ->
                {:ok, %{request | body: body}, rest}
              _ ->
                {:more, {:body, request}, buffer}
            end
          false ->
            reason = {:body_too_large, length}
            # TODO exceptions to include what to do next
            {:error, reason, :close}
        end
    end
  end

  def add_header(request = %{headers: headers}, :Host, location) do
    [host, port] = case String.split(location, ":") do
      [host, port] -> [host, :erlang.binary_to_integer(port)]
      [host] -> [host, 80]
    end
    headers = headers ++ [{"host", location}]
    %{request | headers: headers, host: host, port: port}
  end
  def add_header(request = %{headers: headers}, key, value) do
    key = String.downcase("#{key}")
    headers = headers ++ [{key, value}]
    %{request | headers: headers}
  end
end
