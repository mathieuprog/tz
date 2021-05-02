defmodule Tz do
  alias Tz.PeriodsProvider

  defdelegate database_version(), to: PeriodsProvider
end
