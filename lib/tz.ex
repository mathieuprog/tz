defmodule Tz do
  alias Tz.PeriodsGenerator.PeriodsProvider

  defdelegate version(), to: PeriodsProvider
end
