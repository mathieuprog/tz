defmodule Tz.HTTP.HTTPClient do
  @moduledoc """
  A behaviour allowing to plug in any HTTP client.
  """

  @callback request(String.t(), String.t()) :: struct | nil
end
