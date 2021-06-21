defmodule UpdaterTest do
  use ExUnit.Case

  test "test updater is only started once" do
    assert {:ok, _} = start_supervised(Tz.UpdatePeriodically)
    assert {:error, _} = start_supervised(Tz.UpdatePeriodically)

    assert {:ok, _} = start_supervised(Tz.WatchPeriodically)
    assert {:error, _} = start_supervised(Tz.WatchPeriodically)
  end
end
