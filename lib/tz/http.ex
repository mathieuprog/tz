defmodule Tz.HTTP do
  http_client =
    case Application.fetch_env(:tz, :http_client) do
      {:ok, http_client} ->
        http_client

      :error ->
        cond do
          Code.ensure_loaded?(Mint.HTTP) ->
            Tz.HTTP.Mint.HTTPClient

          true ->
            nil
        end
    end

  def get_http_client!() do
    if unquote(http_client) do
      unquote(http_client)
    else
      raise "No HTTP client found. Add `:mint` as a dependency, or pass a custom HTTP client to the config."
    end
  end
end
