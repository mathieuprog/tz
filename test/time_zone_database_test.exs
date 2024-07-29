defmodule TimeZoneDatabaseTest do
  use ExUnit.Case

  alias Support.HoloceneCalendar

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
    assert Regex.match?(~r/202[2-9][a-z]/, Tz.iana_version())
  end

  test "time_zone_period_from_utc_iso_days with 0 and negative year" do
    utc_period = %{std_offset: 0, utc_offset: 0, zone_abbr: "UTC"}
    belgian_period = %{std_offset: 0, utc_offset: 1050, zone_abbr: "LMT"}

    iso_days = Calendar.ISO.naive_datetime_to_iso_days(0, 1, 1, 0, 0, 0, {0, 6})

    assert {:ok, utc_period} ==
             Tz.TimeZoneDatabase.time_zone_period_from_utc_iso_days(iso_days, "Etc/UTC")

    assert {:ok, belgian_period} ==
             Tz.TimeZoneDatabase.time_zone_period_from_utc_iso_days(iso_days, "Europe/Brussels")

    iso_days = Calendar.ISO.naive_datetime_to_iso_days(-1, 1, 1, 0, 0, 0, {0, 6})

    assert {:ok, utc_period} ==
             Tz.TimeZoneDatabase.time_zone_period_from_utc_iso_days(iso_days, "Etc/UTC")

    assert {:ok, belgian_period} ==
             Tz.TimeZoneDatabase.time_zone_period_from_utc_iso_days(iso_days, "Europe/Brussels")
  end

  test "time_zone_periods_from_wall_datetime with 0 and negative year" do
    utc_period = %{std_offset: 0, utc_offset: 0, zone_abbr: "UTC"}
    belgian_period = %{std_offset: 0, utc_offset: 1050, zone_abbr: "LMT"}

    naive_datetime = NaiveDateTime.new!(0, 1, 1, 0, 0, 0, {0, 6})

    assert {:ok, utc_period} ==
             Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(naive_datetime, "Etc/UTC")

    assert {:ok, belgian_period} ==
             Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(
               naive_datetime,
               "Europe/Brussels"
             )

    naive_datetime = NaiveDateTime.new!(-1, 1, 1, 0, 0, 0, {0, 6})

    assert {:ok, utc_period} ==
             Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(naive_datetime, "Etc/UTC")

    assert {:ok, belgian_period} ==
             Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(
               naive_datetime,
               "Europe/Brussels"
             )
  end

  test "convert non-iso datetime to iso" do
    non_iso_datetime = NaiveDateTime.convert!(~N[2000-01-01 13:30:15], HoloceneCalendar)

    assert Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(non_iso_datetime, "Etc/UTC")

    assert Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(
             non_iso_datetime,
             "Europe/Brussels"
           )
  end

  test "fix issue #24" do
    date_time_utc = ~U[2029-12-31 10:15:00Z]
    time_zone = "Pacific/Chatham"

    zoned_date_time = date_time_utc |> DateTime.shift_zone!(time_zone, Tz.TimeZoneDatabase)
    # #DateTime<2030-01-01 00:00:00+13:45 +1345 Pacific/Chatham>

    naive_datetime = DateTime.to_naive(zoned_date_time)
    # ~N[2030-01-01 00:00:00]

    assert zoned_date_time == DateTime.from_naive!(naive_datetime, time_zone, Tz.TimeZoneDatabase)

    naive_datetime = NaiveDateTime.from_iso8601!("2030-01-01T00:00:00")
    datetime = DateTime.from_naive!(naive_datetime, "Europe/Lisbon", Tz.TimeZoneDatabase)

    assert DateTime.to_iso8601(datetime) == "2030-01-01T00:00:00+00:00"
  end

  test "next_period/1" do
    {:ok, dt} =
      DateTime.new(~D[2030-09-01], ~T[10:00:00], "Europe/Copenhagen", Tz.TimeZoneDatabase)

    {from, _, _, _} = Tz.PeriodsProvider.next_period(dt)

    datetime_next_period =
      DateTime.from_gregorian_seconds(from)
      |> DateTime.shift_zone!(dt.time_zone, Tz.TimeZoneDatabase)

    {:ambiguous, first_dt, second_dt} =
      DateTime.new(~D[2030-10-27], ~T[02:00:00], "Europe/Copenhagen", Tz.TimeZoneDatabase)

    assert DateTime.compare(datetime_next_period, second_dt) == :eq

    {from, _, _, _} = Tz.PeriodsProvider.next_period(second_dt)

    datetime_next_period =
      DateTime.from_gregorian_seconds(from)
      |> DateTime.shift_zone!(dt.time_zone, Tz.TimeZoneDatabase)

    {:gap, _dt_just_before, dt_just_after} =
      DateTime.new(~D[2031-03-30], ~T[02:30:00], "Europe/Copenhagen", Tz.TimeZoneDatabase)

    assert DateTime.compare(datetime_next_period, dt_just_after) == :eq

    {from, _, _, _} = Tz.PeriodsProvider.next_period(first_dt)

    datetime_next_period =
      DateTime.from_gregorian_seconds(from)
      |> DateTime.shift_zone!(dt.time_zone, Tz.TimeZoneDatabase)

    {:ambiguous, _first_dt, second_dt} =
      DateTime.new(~D[2030-10-27], ~T[02:00:00], "Europe/Copenhagen", Tz.TimeZoneDatabase)

    assert DateTime.compare(datetime_next_period, second_dt) == :eq
  end
end
