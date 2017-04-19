defmodule Ace.ChunkedResponse do
  @moduledoc """
  Stream a response to a client as a series of chunks.

  Use when sending large response,
  or to enable servers to push data for example using [server sent events](https://hexdocs.pm/server_sent_event).

  A chunked response is an extension to the Raxx Response model.
  Basic behaviour is for a request to be mapped to a complete response.

  ```
  handle_request(request) :: response
  ```

  When streaming a request is mapped to a stream of content.
  The stream head is an `Ace.ChunkedResponse`,
  subsequent parts of the stream will be an `Ace.Chunk`.

  ```
  handle_request(request) :: stream_head
  handle_info(message) :: [stream_part || stream_terminator]
  ```

  A server indicates a response will be streamed using this module.
  The start of a chunked response must include status and headers.
  It can optionally include a list of chunks that will be sent first.
  The server may also return a new app (`{module, config}`) to handle messages,
  if no app is given the application that originally handled the request is used.

  Once serving a chunked response the handle_info callback will be invoked for every message received by the server.
  This callback must return a list of zero or more chunks to stream to the client.

  Chunks are any io_data.
  An empty chunk `""` is considered to be the terminator.
  A connection will be closed after sending a terminator chunk.

  ## Example


  ```elixir
  defmodule do
    # Send chunked response from "GET /stream"
    def handle_request(%{path: ["stream"], method: :GET}, _) do
      %Ace.ChunkedResponse{
        status: 200,
        headers: [{"transfer-encoding", "chunked"}, {"cache-control", "no-cache"}]
      }
    end

    # Send data as a single chunk
    def handle_info({:chunk, data}, _) do
      [data]
    end

    # Don't sent any data
    def handle_info(:info, _) do
      []
    end

    # Indicate the response has no more content to stream
    def handle_info(:done, _) do
      [""]
    end

  end
  ```

  ## Struct

  | **status** | The HTTP status code for the response: `1xx, 2xx, 3xx, 4xx, 5xx` |
  | **headers** | The response headers as a list: `[{"content-type", "text/plain"}` |
  | **chunks** | List of chunks to send as the start of a stream. default `[]` |
  | **app** | Optional upgrade to server to handle streaming. default `nil` |
  """

  defstruct [
    status: nil,
    headers: [],
    app: nil,
    chunks: []
  ]
end
