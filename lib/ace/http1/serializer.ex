defmodule Ace.HTTP1.Serializer do
  @enforce_keys [
    :next,
  ]

  defstruct @enforce_keys

  def new() do
    %__MODULE__{next: :head}
  end

  def serialize(head = %{body: false}, %{next: :head}) do
    head = head
    |> Ace.Raxx.delete_header("content-length")
    |> Raxx.set_header("content-length", "0")
    state = %{next: :done}
    {:ok, {serialize_head(head), state}}
  end
  def serialize(head = %{body: true}, %{next: :head}) do
    case Ace.Raxx.content_length(head) do
      nil ->
        head = head
        |> Ace.Raxx.delete_header("transfer-encoding")
        |> Raxx.set_header("transfer-encoding", "chunked")
        {:ok, {serialize_head(head), %__MODULE__{next: :chunked_body}}}
      length when length > 0 ->
        {:ok, {serialize_head(head), %__MODULE__{next: {:body, length}}}}
    end
  end
  def serialize(message = %{body: body}, %{next: :head}) when is_binary(body) do
    content_length = Ace.Raxx.content_length(message) || :erlang.iolist_size(body)
    message = Ace.Raxx.delete_header(message, "content-length")
    message = Raxx.set_header(message, "content-length", content_length)
    # Could call serialize body to check too long too short or already chunked
    {:ok, {serialize_head(message) <> body, %__MODULE__{next: :done}}}
  end

  # TODO check correct quantity of data is sent
  def serialize(%Raxx.Data{data: data}, state = %{next: {:body, _remainig}}) do
    {:ok, {data, state}}
  end
  def serialize(%Raxx.Tail{}, state = %{next: {:body, _remainig}}) do
    {:ok, {"", %{state | next: :done}}}
  end

  # Keep chunked together
  def serialize(%Raxx.Data{data: data}, state = %{next: :chunked_body}) do
    {:ok, {serialize_chunk(data), state}}
  end
  def serialize(%Raxx.Tail{}, state = %{next: :chunked_body}) do
    {:ok, {serialize_chunk(""), %{state | next: :done}}}
  end
#
  defp serialize_head(response = %Raxx.Response{}) do
    [
      "HTTP/1.1 #{response.status} #{Raxx.reason_phrase(response.status)}\r\n",
      header_lines(response.headers),
      "\r\n",
    ]
    |> :erlang.iolist_to_binary()
  end

  @doc """
  Serialize io_data as a single chunk to be streamed.

  ## Example

      iex> Ace.HTTP1.serialize_chunk("hello")
      ...> |> to_string()
      "5\\r\\nhello\\r\\n"

      iex> Ace.HTTP1.serialize_chunk("")
      ...> |> to_string()
      "0\\r\\n\\r\\n"
  """
  def serialize_chunk(data) do
    size = :erlang.iolist_size(data)
    [:erlang.integer_to_list(size, 16), "\r\n", data, "\r\n"]
  end

  defp header_lines(headers) do
    Enum.map(headers, &header_line/1)
  end

  defp header_line({field_name, field_value}) do
    "#{field_name}: #{field_value}\r\n"
  end
end
