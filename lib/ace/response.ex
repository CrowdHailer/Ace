defmodule Ace.Response do
  @moduledoc """
  Encapsulate parameters for HTTP stream from server to client.

  | **status** | The HTTP status code for the response: `1xx, 2xx, 3xx, 4xx, 5xx` |
  | **headers** | The headers from the HTTP request as an array of string pairs. Note all headers will be downcased, e.g. [{"content-type", "text/plain"}] |
  | **body** | `true`, `false` or complete body as a binary. |
  """

  @enforce_keys [:status, :headers, :body]
  defstruct @enforce_keys

  @doc """
  Construct a new response
  """
  def new(status, headers, body) do
    %__MODULE__{
      status: status,
      headers: headers,
      body: body,
    }
  end
end
