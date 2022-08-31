defmodule TimeZoneDatabaseTest do
  use ExUnit.Case

  test "naive date for time zone" do
    naive_date_time = ~N[2018-07-28 12:30:00]
    time_zone = "Europe/Copenhagen"

    result = DateTime.from_naive(naive_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:ok, datetime} = result

    assert DateTime.to_iso8601(datetime) == "2018-07-28T12:30:00+02:00"
    assert datetime.time_zone == "Europe/Copenhagen"
    assert datetime.zone_abbr == "CEST"
  end

  test "time zone link" do
    naive_date_time = ~N[2018-07-28 12:30:00]
    time_zone = "Europe/Mariehamn"

    result = DateTime.from_naive(naive_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:ok, datetime} = result

    assert datetime.time_zone == "Europe/Mariehamn"
  end

  test "naive date is ambiguous date for time zone" do
    naive_date_time = ~N[2018-10-28 02:30:00]
    time_zone = "Europe/Copenhagen"

    result = DateTime.from_naive(naive_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:ambiguous, first_dt, second_dt} = result

    assert DateTime.to_iso8601(first_dt) == "2018-10-28T02:30:00+02:00"
    assert DateTime.to_iso8601(second_dt) == "2018-10-28T02:30:00+01:00"
    assert first_dt.time_zone == "Europe/Copenhagen"
    assert first_dt.zone_abbr == "CEST"
    assert second_dt.time_zone == "Europe/Copenhagen"
    assert second_dt.zone_abbr == "CET"
  end

  test "naive date date is in gap for time zone" do
    naive_date_time = ~N[2019-03-31 02:30:00]
    time_zone = "Europe/Copenhagen"

    result = DateTime.from_naive(naive_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:gap, just_before, just_after} = result

    assert DateTime.to_iso8601(just_before) == "2019-03-31T01:59:59.999999+01:00"
    assert DateTime.to_iso8601(just_after) == "2019-03-31T03:00:00+02:00"
    assert just_before.time_zone == "Europe/Copenhagen"
    assert just_before.zone_abbr == "CET"
    assert just_after.time_zone == "Europe/Copenhagen"
    assert just_after.zone_abbr == "CEST"
  end

  test "shift UTC date to other time zone" do
    utc_date_time = ~U[2018-07-16 10:00:00Z]
    time_zone = "America/Los_Angeles"

    result = DateTime.shift_zone(utc_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:ok, pacific_datetime} = result

    assert DateTime.to_iso8601(pacific_datetime) == "2018-07-16T03:00:00-07:00"
    assert pacific_datetime.time_zone == "America/Los_Angeles"
    assert pacific_datetime.zone_abbr == "PDT"
  end

  test "time zone not found" do
    naive_date_time = ~N[2000-01-01 00:00:00]
    time_zone = "bad time zone"

    result = DateTime.from_naive(naive_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:error, :time_zone_not_found} = result
  end

  test "far future date" do
    naive_date_time = ~N[2043-12-18 12:30:00]
    time_zone = "Europe/Brussels"

    result = DateTime.from_naive(naive_date_time, time_zone, Tz.TimeZoneDatabase)

    assert {:ok, _datetime} = result
  end

  test "version" do
    assert "2022c" == Tz.iana_version()
  end
end
