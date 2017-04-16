defmodule Ace.HTTP.Handler do
  use Ace.Application
  @moduledoc false
  def handle_connect(conn, app) do
    partial = {:start_line, conn}
    buffer = ""
    # Need to keep track of conn for keep-alive, 4th spot might also be where to keep upgrade
    {:nosend, {app, partial, buffer}}
  end

  def handle_packet(packet, {app, partial, buffer}) do
    case process_buffer(buffer <> packet, partial) do
      {:more, partial, buffer} ->
        {:nosend, {app, partial, buffer}}
      {:ok, request, buffer} ->
        {mod, state} = app
        case mod.handle_request(request, state) do
          chunked_response = %Ace.ChunkedResponse{} ->
            to_write = Ace.Response.serialize(chunked_response)
            app = chunked_response.app || app
            {:send, to_write, {:streaming, app}}
          basic_response = %{body: _, headers: _, status: _} ->
            raw = Ace.Response.serialize(basic_response)
            {:send, raw, {app, {:start_line, %{}}, buffer}}
        end
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

  def handle_disconnect(_reason, {_app, _partial, _buffer}) do
    :ok
  end

  def process_buffer(buffer, {:start_line, conn}) do
    case :erlang.decode_packet(:http_bin, buffer, []) do
      {:more, :undefined} ->
        {:more, {:start_line, conn}, buffer}
      {:ok, {:http_request, method, {:abs_path, path_string}, _version}, rest} ->
        %{path: path, query: query_string} = URI.parse(path_string)
        # DEBT in case of path '//' then parsing returns path of nil.
        # e.g. localhost:8080//
        path = path || "/"
        {:ok, query} = URI2.Query.decode(query_string || "")
        path = Raxx.Request.split_path(path)
        request = %Raxx.Request{method: method, path: path, query: query, headers: []}
        process_buffer(rest, {:headers, request})
    end
  end
  def process_buffer(buffer, {:headers, request}) do
    case :erlang.decode_packet(:httph_bin, buffer, []) do
      {:more, :undefined} ->
        {:more, {:headers, request}, buffer}
      # Key values is binary for unknown headers, atom and capitalised for known.
      {:ok, {:http_header, _, key, _, value}, rest} ->
        process_buffer(rest, {:headers, add_header(request, key, value)})
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
        case buffer do
          <<body :: binary-size(length)>> <> rest ->
            {:ok, %{request | body: body}, rest}
          _ ->
            {:more, {:body, request}, buffer}
        end
    end
  end

  def add_header(request = %{headers: headers}, :Host, location) do
    [host, port] = case String.split(location, ":") do
      [host, port] -> [host, :erlang.binary_to_integer(port)]
      [host] -> [host, 80]
    end
    headers = headers ++ [{"host", location}]
    %{request | headers: headers, host: host, port: port, scheme: "http"}
  end
  def add_header(request = %{headers: headers}, key, value) do
    key = String.downcase("#{key}")
    headers = headers ++ [{key, value}]
    %{request | headers: headers}
  end
end
