defmodule Ace.HTTP2 do
  @moduledoc """
  **Hypertext Transfer Protocol Version 2 (HTTP/2)**

  > HTTP/2 enables a more efficient use of network
  > resources and a reduced perception of latency by introducing header
  > field compression and allowing multiple concurrent exchanges on the
  > same connection.  It also introduces unsolicited push of
  > representations from servers to clients.

  *Quote from [rfc 7540](https://tools.ietf.org/html/rfc7540).*
  """

  import Kernel, except: [send: 2]

  @known_methods ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT"]

  @spec send(Ace.HTTP.Channel.t(), {:promise, Raxx.Request.t()} | Raxx.part()) :: :ok
  def send(stream, request = %{scheme: nil}) do
    send(stream, %{request | scheme: :https})
  end

  def send(stream, item = %type{})
      when type in [Raxx.Request, Raxx.Response, Raxx.Data, Raxx.Tail] do
    %{endpoint: endpoint} = stream
    {:ok, _} = GenServer.call(endpoint, {:send, stream, [item]})
    :ok
  end

  def send(stream, item = {:promise, %Raxx.Request{}}) do
    %{endpoint: endpoint} = stream
    {:ok, _} = GenServer.call(endpoint, {:send, stream, [item]})
    :ok
  end

  @doc """
  Send a ping frame over an HTTP/2 connection.
  """
  def ping(connection, identifier) when bit_size(identifier) == 64 do
    GenServer.call(connection, {:ping, identifier})
  end

  @doc """
  Transform an `Raxx.Request` into a generic headers list.

  This headers list can be encoded via `Ace.HPack`.
  """
  @spec request_to_headers(Raxx.Request.t()) :: Raxx.headers()
  def request_to_headers(request) do
    # TODO consider default values for required scheme and authority
    # DEBT nested queries
    query_string =
      case request.query do
        nil ->
          ""

        query ->
          "?" <> query
      end

    path = "/" <> Enum.join(request.path, "/") <> query_string

    [
      {":scheme", Atom.to_string(request.scheme)},
      {":authority", request.authority || "example.com"},
      {":method", Atom.to_string(request.method)},
      {":path", path}
      | request.headers
    ]
  end

  @doc """
  Transform a `Raxx.Response` into a generic headers list.

  This headers list can be encoded via `Ace.HPack`.
  """
  def response_to_headers(request) do
    [
      {":status", Integer.to_string(request.status)}
      | request.headers
    ]
  end

  @doc """
  Build a `Raxx.Request` from a decoded list of headers.

  Note the required pseudo-headers must be first.
  Request pseudo-headers are; `:scheme`, `:authority`, `:method` & `:path`.
  Duplicate or missing pseudo-headers will return an error.
  """
  # def headers_to_request(headers, end_stream) do
  #   OK.for do
  #     request <- build_request(headers)
  #   after
  #     %{request | body: !end_stream}
  #   end
  # end
  @spec headers_to_request(Raxx.headers(), boolean) ::
          {:ok, Raxx.Request.t()} | {:error, {:protocol_error, String.t()}}
  def headers_to_request(headers, end_stream) do
    case build_request(headers) do
      {:ok, request} ->
        {:ok, %{request | body: !end_stream}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request(request_headers) do
    build_request(request_headers, {:scheme, :authority, :method, :path})
  end

  defp build_request([{":scheme", scheme} | rest], {:scheme, authority, method, path}) do
    case scheme do
      # DEBT can sent headers even be empty?
      "" ->
        {:error, {:protocol_error, "scheme must not be empty"}}

      "https" ->
        build_request(rest, {:https, authority, method, path})

      "http" ->
        build_request(rest, {:http, authority, method, path})
    end
  end

  defp build_request([{":authority", authority} | rest], {scheme, :authority, method, path}) do
    case authority do
      "" ->
        {:error, {:protocol_error, "authority must not be empty"}}

      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end

  defp build_request([{":method", method} | rest], {scheme, authority, :method, path}) do
    case method do
      "" ->
        {:error, {:protocol_error, "method must not be empty"}}

      method when method in @known_methods ->
        method = String.to_atom(method)
        build_request(rest, {scheme, authority, method, path})
    end
  end

  defp build_request([{":path", path} | rest], {scheme, authority, method, :path}) do
    case path do
      "" ->
        {:error, {:protocol_error, "path must not be empty"}}

      _ ->
        build_request(rest, {scheme, authority, method, path})
    end
  end

  defp build_request([{":" <> psudo, _value} | _rest], _required) do
    case psudo do
      psudo when psudo in ["scheme", "authority", "method", "path"] ->
        {:error, {:protocol_error, "pseudo-header sent more than once"}}

      other ->
        {:error, {:protocol_error, "unacceptable pseudo-header, :#{other}"}}
    end
  end

  defp build_request(headers, {scheme, authority, method, path}) do
    if scheme == :scheme or authority == :authority or method == :method or path == :path do
      {:error, {:protocol_error, "All pseudo-headers must be sent"}}
    else
      case read_headers(headers) do
        {:ok, headers} ->
          request = %{
            Raxx.request(method, path)
            | scheme: scheme,
              authority: authority,
              headers: headers
          }

          {:ok, request}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Build a `Raxx.Response` from a decoded list of headers.

  Note the required pseudo-headers must be first.
  Response pseudo-headers are; `:status`.
  Duplicate or missing pseudo-headers will return an error.
  """
  @spec headers_to_response(Raxx.headers(), boolean) :: {:ok, Raxx.Response.t()}
  def headers_to_response([{":status", status} | headers], end_stream) do
    case read_headers(headers) do
      {:ok, headers} ->
        {status, ""} = Integer.parse(status)
        response = %{Raxx.response(status) | headers: headers, body: !end_stream}
        {:ok, response}
    end
  end

  @doc """
  Transform a list of decoded headers to a trailers structure.

  Note there are no required headers in a trailers set.
  """
  @spec headers_to_trailers(Raxx.headers()) ::
          %{headers: Raxx.headers(), end_stream: true} | {:error, {:protocol_error, String.t()}}
  def headers_to_trailers(headers) do
    {:ok, headers} = read_headers(headers)
    %{headers: headers, end_stream: true}
  end

  defp read_headers(raw, acc \\ [])

  defp read_headers([], acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp read_headers([{":" <> _, _} | _], _acc) do
    {:error, {:protocol_error, "pseudo-header sent amongst normal headers"}}
  end

  defp read_headers([{"connection", _} | _rest], _acc) do
    {:error, {:protocol_error, "connection header must not be used with HTTP/2"}}
  end

  defp read_headers([{"te", value} | rest], acc) do
    case value do
      "trailers" ->
        read_headers(rest, [{"te", value} | acc])

      _ ->
        {
          :error,
          {:protocol_error, "TE header field with any value other than 'trailers' is invalid"}
        }
    end
  end

  defp read_headers([{k, v} | rest], acc) do
    case String.downcase(k) == k do
      true ->
        read_headers(rest, [{k, v} | acc])

      false ->
        {:error, {:protocol_error, "headers must be lower case"}}
    end
  end
end
