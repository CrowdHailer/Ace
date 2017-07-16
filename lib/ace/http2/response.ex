defmodule Ace.HTTP2.Response do
  defstruct [
    :sent, # nil/headers/body/complete
    :status,
    :headers,
    :body, # maybe call this buffer as we will clear it on each turn of the state machine
    :finish # true or trailers
  ]

  def new() do
    %__MODULE__{sent: :none, headers: %{}}
  end

  def headers_to_send(response) do
    case {response.sent, response.status} do
      {_, nil} ->
        nil
      {:none, status_code} ->
        Map.merge(response.headers, %{":status" => "#{status_code}"})
    end
  end

  def body_to_send(response) do
    case {response.sent, response.body} do
      {:complete, _} ->
        nil
      {_, data} ->
        data
    end
  end
  def process(response, outbound \\ []) do
    case response.sent do
      :none ->
        if response.status do
          headers = headers(response)
          # sent = if response.finish, do: :complete, else: :headers
          # headers ++ stream_end
          process(%{response | sent: :headers}, [headers])
        else
          {[], response}
        end
      :headers ->
        outbound = if response.body do
          outbound
        else
          outbound ++ [{:data, response.body}]
        end

        if response.finish do
          IO.inspect(outbound)
        end
    end
  end

  def set_status(response = %{sent: :none, status: nil}, status_code) when is_integer(status_code) do
    %{response | status: status_code}
  end
  def put_header(response = %{sent: :none, headers: headers}, key, value) do
    headers = Map.put(headers, key, value)
    %{response | headers: headers}
  end
  def send_data(response = %{sent: sent, body: buffer}, data) when sent in [:none, :headers] do
    buffer = (buffer || "") <> data
    %{response | body: buffer}
  end
  def finish(response) do
    %{response | finish: true}
  end

  def headers(%{status: status_code, headers: headers}) do
    Map.merge(headers, %{":status" => "#{status_code}"})
  end

  def has_headers do
    # is status set
  end
  def read_headers do
    # status + headers OR nil
  end
  def read_body do
    # binary OR {binary, :end}, or None
  end

  # test
  # fresh + nil = [] sent: nil
  # fresh + status = [headers] sent: headers
  # fresh + status + headers = [headers] sent: headers
  # fresh + status + headers + body = [headers] sent: headers
  # fresh + status + headers + body + push_promise + finish sent: finish

end
