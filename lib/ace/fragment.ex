defmodule Ace.Fragment do
  @moduledoc """
  Part of the body of a Request or Response

  """

  @enforce_keys [:body, :end_stream]
  defstruct @enforce_keys

  def new(body, end_stream \\ false) do
    %__MODULE__{
      body: body,
      end_stream: end_stream
    }
  end
end
