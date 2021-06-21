defmodule Tz.HTTP.HTTPClient do
  @callback request(String.t(), String.t()) :: struct
end
