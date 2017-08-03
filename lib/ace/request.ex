defmodule Ace.Request do
  @enforce_keys [:method, :path, :headers, :body]
  defstruct @enforce_keys ++ [:authority, :scheme]

  def get(path, headers \\ []) do
    new(:GET, path, headers, false)
  end

  def put(path, headers, body) do
    new(:PUT, path, headers, body)
  end

  def new(method, path, headers, body) do
    %__MODULE__{
      scheme: :https,
      authority: :connection,
      method: method,
      path: path,
      headers: headers,
      body: body
    }
  end

  def complete?(%__MODULE__{body: body}) when is_binary(body) do
    true
  end
  def complete?(%__MODULE__{body: body}) do
    !body
  end
end
