defmodule DynamicPeriodsTest do
  use ExUnit.Case

  test "test dynamic periods" do
    time_zone = "Antarctica/Troll"

    {:ok, datetime} =
      DateTime.from_naive!(~N[2050-05-14 07:30:00], "Etc/UTC", Tz.TimeZoneDatabase)
      |> DateTime.shift_zone(time_zone, Tz.TimeZoneDatabase)

    assert DateTime.to_iso8601(datetime) == "2050-05-14T09:30:00+02:00"
    assert datetime.time_zone == time_zone
    assert datetime.zone_abbr == "+02"

    {:ok, datetime} =
      DateTime.from_naive!(~N[2050-12-14 07:30:00], "Etc/UTC", Tz.TimeZoneDatabase)
      |> DateTime.shift_zone(time_zone, Tz.TimeZoneDatabase)

    assert DateTime.to_iso8601(datetime) == "2050-12-14T07:30:00+00:00"
    assert datetime.time_zone == time_zone
    assert datetime.zone_abbr == "+00"
  end
end
