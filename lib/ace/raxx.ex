defmodule Ace.Raxx do
  def get_header(%{headers: headers}, header) do
    case :proplists.get_all_values(header, headers) do
      [] ->
        nil
      [value] ->
        value
      _ ->
        raise "More than one header found for `#{header}`"
    end
  end

  def delete_header(message = %{headers: headers}, header) do
    headers = :proplists.delete(header, headers)
    %{message | headers: headers}
  end

  def content_length(message) do
    if raw = get_header(message, "content-length") do
      {content_length, ""} = Integer.parse(raw)
      content_length
    end
  end
end
