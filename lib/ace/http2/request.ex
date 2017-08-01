# DEBT move to Ace.Request
defmodule Ace.HTTP2.Request do
  # @enforce_keys [:scheme, :authority, :method, :path, :headers]
  defstruct [:scheme, :authority, :method, :path, :headers, :body]

  def to_headers(request = %__MODULE__{}) do
    [
      {":scheme", Atom.to_string(request.scheme)},
      {":authority", request.authority},
      {":method", Atom.to_string(request.method)},
      {":path", request.path} |
      Map.to_list(request.headers)
    ]
  end

  def from_headers(headers) do
    headers
    |> Enum.reduce(%__MODULE__{headers: []}, &add_header/2)
  end

  def add_header({":method", method}, request = %{method: nil}) do
    %{request | method: method}
  end
  def add_header({":path", path}, request = %{path: nil}) do
    %{request | path: path}
  end
  def add_header({":scheme", scheme}, request = %{scheme: nil}) do
    %{request | scheme: scheme}
  end
  def add_header({":authority", authority}, request = %{authority: nil}) do
    %{request | authority: authority}
  end
  def add_header({key, value}, request = %{headers: headers}) do
    # TODO test key does not begin with `:`
    # headers = Map.put(headers || %{}, key, value)
    headers = headers ++ [{key, value}]
    %{request | headers: headers}
  end
end
