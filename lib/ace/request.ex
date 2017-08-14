defmodule Ace.Request do
  @moduledoc """
  Encapsulate parameters used to open an HTTP stream.

  This module is for working with requests.
  A request can be sent over a stream using the `Ace.Client`

  | **method** | The HTTP request method, such as “GET” or “POST”, as an atom; always uppercase. |
  | **path** | Path to the resource requested |
  | **headers** | The headers from the HTTP request as an array of string pairs. Note all headers will be downcased, e.g. [{"content-type", "text/plain"}] |
  | **body** | `true`, `false` or complete body as a binary. |
  | **authority("example.com")** | The host and port of the server. |
  | **scheme(:https)** | `:http` or `:https`, depending on the transport used. |

  *() default value*

  """
  @enforce_keys [:method, :path, :headers, :body, :authority, :scheme]
  defstruct @enforce_keys

  @doc """
  Construct a new GET request.
  """
  def get(path, headers \\ []) do
    new(:GET, path, headers, false)
  end

  @doc """
  Construct a new HEAD request.
  """
  def head(path, headers \\ []) do
    new(:HEAD, path, headers, false)
  end

  @doc """
  Construct a new POST request.
  """
  def post(path, headers, body) do
    new(:POST, path, headers, body)
  end

  @doc """
  Construct a new PUT request.
  """
  def put(path, headers, body) do
    new(:PUT, path, headers, body)
  end

  @doc """
  Construct a new PATCH request.
  """
  def patch(path, headers, body) do
    new(:PATCH, path, headers, body)
  end

  @doc """
  Construct a new DELETE request.
  """
  def delete(path, headers, body) do
    new(:DELETE, path, headers, body)
  end

  @doc """
  Construct a new request.
  """
  def new(method, path, headers, body, opts \\ []) do
    scheme = Keyword.get(opts, :scheme, :https)
    authority = Keyword.get(opts, :scheme, "example.com")
    %__MODULE__{
      scheme: scheme,
      authority: authority,
      method: method,
      path: path,
      headers: headers,
      body: body
    }
  end

  @doc """
  Just the request contain all content the will be part of the request stream.
  """
  def complete?(%__MODULE__{body: body}) when is_binary(body) do
    true
  end
  def complete?(%__MODULE__{body: body}) do
    !body
  end
end
