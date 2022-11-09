defmodule Tz.HTTP do
  @doc """
  Return the http client module configured for tz.
  """
  def get_http_client!() do
    case Application.get_env(:tz, :http_client) do
      nil -> default_client!()
      client -> client
    end
  end

  defp default_client!() do
    if Code.ensure_loaded?(Mint.HTTP) do
      Tz.HTTP.Mint.HTTPClient
    else
      raise "No HTTP client found. Add :mint as a dependency, or specify a custom HTTP client by the :http_client environment variable."
    end
  end
end
