defmodule Tz do
  alias Tz.PeriodsProvider

  @doc """
  Returns the IANA time zone database version.
  """
  defdelegate iana_version(), to: PeriodsProvider
end
