defmodule Tz do
  alias Tz.PeriodsProvider

  defdelegate version(), to: PeriodsProvider
end
