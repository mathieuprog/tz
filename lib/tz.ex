defmodule Tz do
  alias Tz.PeriodsProvider

  defdelegate iana_version(), to: PeriodsProvider
end
