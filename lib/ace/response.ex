defmodule Ace.Response do
  @enforce_keys [:status, :headers, :body]
  defstruct @enforce_keys

  def new(status, headers, body) do
    %__MODULE__{
      status: status,
      headers: headers,
      body: body,
    }
  end
end
