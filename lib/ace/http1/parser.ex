defmodule Ace.HTTP1.Parser do
  @moduledoc """
  Incrementally parse an HTTP/1.x request.
  """

  @typedoc """
  Available options when initializing a new parser
  """
  @type option :: {:max_line_length, integer}

  @typep buffer :: String.t()
  @typep read_start_line :: {:start_line, buffer, map}
  @typep read_headers :: {:headers, buffer, HttpRequest, [HttpHeader], map}
  @typep read_body :: {:body, buffer, non_neg_integer, map}
  @typep read_body_chunked :: {:body_chunked, buffer, map}
  @typep read_trailers :: {:trailers, buffer, map}
  @typep read_done :: {:done, buffer, map}

  @typedoc """
  State tracking the progress of the Parser.
  """
  @opaque state ::
            read_start_line
            | read_headers
            | read_body
            | read_body_chunked
            | read_trailers
            | read_done

  @doc """
  Initial state for the incremental parser.
  """
  @spec new([option]) :: state
  def new(opts) do
    max_line_length = Keyword.get(opts, :max_line_length)
    {:start_line, "", %{max_line_length: max_line_length}}
  end

  @doc """
  Run the parser aginst a some new input.

  This parser returns a list of parts that are in the input and an updated state.
  """
  @spec parse(String.t(), state, [Raxx.Server.part()]) ::
          {:ok, {[Raxx.Server.part()], state}} | {:error, binary}
  def parse(binary, state, parts \\ []) do
    state = append_buffer(state, binary)

    case pop_part(state) do
      {:ok, {nil, new_state}} ->
        {:ok, {parts, new_state}}

      {:ok, {new_part, new_state}} ->
        parse("", new_state, parts ++ [new_part])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Has the parser consumed and entire HTTP message?
  """
  @spec done?(state) :: boolean
  def done?({:done, _, _}) do
    true
  end

  def done?(_state) do
    false
  end

  defp append_buffer({:start_line, buffer, options}, binary) do
    {:start_line, buffer <> binary, options}
  end

  defp append_buffer({:headers, buffer, start_line, headers, options}, binary) do
    {:headers, buffer <> binary, start_line, headers, options}
  end

  defp append_buffer({:body, buffer, remaining, options}, binary) do
    {:body, buffer <> binary, remaining, options}
  end

  defp append_buffer({:body_chunked, buffer, options}, binary) do
    {:body_chunked, buffer <> binary, options}
  end

  defp append_buffer({:trailers, buffer, options}, binary) do
    {:trailers, buffer <> binary, options}
  end

  defp append_buffer({:done, overflow, options}, binary) do
    {:done, overflow <> binary, options}
  end

  defp pop_part(state = {:start_line, buffer, options}) do
    case :erlang.decode_packet(:http_bin, buffer, line_length: options.max_line_length) do
      {:more, :undefined} ->
        {:ok, {nil, state}}

      {:ok, start_line = {:http_request, _, _, _}, rest} ->
        pop_part({:headers, rest, start_line, [], options})

      {:ok, {:http_error, line}, _rest} ->
        {:error, {:invalid_start_line, line}}

      {:error, :invalid} ->
        {:error, :start_line_too_long}
    end
  end

  defp pop_part(state = {:headers, buffer, start_line, headers, options}) do
    case :erlang.decode_packet(:httph_bin, buffer, []) do
      {:more, :undefined} ->
        {:ok, {nil, state}}

      {:ok, {:http_header, _, key, _, value}, rest} ->
        new_headers = headers ++ [{String.downcase("#{key}"), value}]
        pop_part({:headers, rest, start_line, new_headers, options})

      {:ok, :http_eoh, rest} ->
        # NOTE: transfer-encoding is not part of HTTP/2 spec, header is removed before parsing to Ace.Worker.
        {transfer_encoding, clean_headers} = resolve_transfer_encoding(headers)
        clean_headers = :proplists.delete("connection", clean_headers)

        request_head =
          Enum.reduce(
            :proplists.delete("host", clean_headers),
            build_partial_request(start_line, :proplists.get_value("host", headers)),
            fn {k, v}, request -> Raxx.set_header(request, k, v) end
          )

        case transfer_encoding do
          nil ->
            case content_length(headers) do
              length when length in [0, nil] ->
                {:ok, {request_head, {:done, rest, options}}}

              length ->
                {:ok, {request_head |> Raxx.set_body(true), {:body, rest, length, options}}}
            end

          "chunked" ->
            {:ok, {request_head |> Raxx.set_body(true), {:body_chunked, rest, options}}}
        end

      {:ok, {:http_error, line}, _rest} ->
        {:error, {:invalid_header_line, line}}
    end
  end

  defp pop_part({:body, "", remaining, options}) do
    {:ok, {nil, {:body, "", remaining, options}}}
  end

  defp pop_part({:body, buffer, remaining, options}) when byte_size(buffer) < remaining do
    part = Raxx.data(buffer)
    {:ok, {part, {:body, "", remaining - byte_size(buffer), options}}}
  end

  defp pop_part({:body, buffer, remaining, options}) when byte_size(buffer) >= remaining do
    <<data::binary-size(remaining), rest::binary>> = buffer
    {:ok, {Raxx.data(data), {:trailers, rest, options}}}
  end

  defp pop_part({:body_chunked, buffer, options}) do
    {chunk, rest} = pop_chunk(buffer)

    case chunk do
      nil ->
        {:ok, {nil, {:body_chunked, buffer, options}}}

      "" ->
        {:ok, {Raxx.tail([]), {:done, rest, options}}}

      chunk ->
        {:ok, {Raxx.data(chunk), {:body_chunked, rest, options}}}
    end
  end

  defp pop_part({:trailers, buffer, options}) do
    {:ok, {Raxx.tail([]), {:done, buffer, options}}}
  end

  defp pop_part(state = {:done, _overflow, _options}) do
    {:ok, {nil, state}}
  end

  defp resolve_transfer_encoding(headers) do
    case :proplists.get_value("transfer-encoding", headers) do
      :undefined ->
        {nil, headers}

      binary ->
        {binary, :proplists.delete("transfer-encoding", headers)}
    end
  end

  defp content_length(headers) do
    case :proplists.get_value("content-length", headers) do
      :undefined ->
        nil

      binary ->
        {content_length, ""} = Integer.parse(binary)
        content_length
    end
  end

  defp build_partial_request({:http_request, method, http_uri, _version}, host) do
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

    # NOTE scheme is ignored from message.
    # It should therefore not be part of request but part of connection. same as client ip etc
    # However scheme is a required header in HTTP/2
    # Q? how often is a host header sent with http in place
    # %{scheme: scheme} = URI.parse(host)

    %Raxx.Request{
      scheme: nil,
      authority: host,
      method: method,
      path: path,
      query: query,
      headers: [],
      body: false
    }
  end

  defp pop_chunk(buffer) do
    case String.split(buffer, "\r\n", parts: 2) do
      [base_16_size, rest] ->
        size =
          base_16_size
          |> :erlang.binary_to_list()
          |> :erlang.list_to_integer(16)

        case rest do
          <<chunk::binary-size(size), "\r\n", rest::binary>> ->
            {chunk, rest}

          _incomplete_chunk ->
            {nil, buffer}
        end

      [rest] ->
        {nil, rest}
    end
  end
end
