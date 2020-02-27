defmodule Tz do
  alias Tz.PeriodsGenerator.PeriodsProvider

  defdelegate version(), to: PeriodsProvider
  defdelegate periods(time_zone), to: PeriodsProvider
end
