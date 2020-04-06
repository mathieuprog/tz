defmodule Tz.TimeZoneDatabase do
  @moduledoc false

  @behaviour Calendar.TimeZoneDatabase

  alias Tz.IanaFileParser
  alias Tz.PeriodsBuilder
  alias Tz.PeriodsProvider

  @impl true
  def time_zone_period_from_utc_iso_days(iso_days, time_zone) do
    with {:ok, periods_by_year} <- PeriodsProvider.periods_by_year(time_zone) do
      naive_datetime = naive_datetime_from_iso_days(iso_days)
      utc_gregorian_seconds = NaiveDateTime.diff(naive_datetime, ~N[0000-01-01 00:00:00])

      found_periods =
        Map.get(periods_by_year, naive_datetime.year, periods_by_year.minmax)
        |> find_periods_for_timestamp(utc_gregorian_seconds, :utc_gregorian_seconds)

      case found_periods do
        [period] ->
          {:ok, period}
        _ ->
          raise "#{Enum.count(found_periods)} periods found"
      end
    end
  end

  @impl true
  def time_zone_periods_from_wall_datetime(naive_datetime, time_zone) do
    with {:ok, periods_by_year} <- PeriodsProvider.periods_by_year(time_zone) do
      wall_gregorian_seconds = NaiveDateTime.diff(naive_datetime, ~N[0000-01-01 00:00:00])

      found_periods =
        Map.get(periods_by_year, naive_datetime.year, periods_by_year.minmax)
        |> find_periods_for_timestamp(wall_gregorian_seconds, :wall_gregorian_seconds)

      case found_periods do
        [%{zone_abbr: _} = period] ->
          {:ok, period}
        [%{period_before_gap: _} = period] ->
          {:gap, {period.period_before_gap, period.from.wall}, {period.period_after_gap, period.to.wall}}
        [second_period, first_period] ->
          {:ambiguous, first_period, second_period}
        _ ->
          raise "#{Enum.count(found_periods)} periods found"
      end
    end
  end

  defp generate_dynamic_periods([period1, period2], year) do
    rule_records = IanaFileParser.denormalized_rule_data([
      IanaFileParser.change_rule_year(period1.rule, year - 1),
      IanaFileParser.change_rule_year(period1.rule, year),
      IanaFileParser.change_rule_year(period2.rule, year)
    ])

    PeriodsBuilder.build_periods([period1.zone_line], rule_records)
    |> PeriodsBuilder.shrink_and_reverse_periods()
  end

  defp find_periods_for_timestamp(periods, timestamp, time_modifier) do
    do_find_periods_for_timestamp(periods, timestamp, time_modifier)
    |> maybe_generate_dynamic_periods(periods, timestamp, time_modifier)
  end

  defp do_find_periods_for_timestamp(periods, timestamp, time_modifier) do
    Enum.filter(periods, fn period ->
      period_from = if(period.from == :min, do: :min, else: period.from[time_modifier])
      period_to = if(period.to == :max, do: :max, else: period.to[time_modifier])

      is_timestamp_in_range?(timestamp, period_from, period_to)
    end)
  end

  defp is_timestamp_in_range?(_, :min, :max), do: true
  defp is_timestamp_in_range?(timestamp, :min, date_to), do: timestamp < date_to
  defp is_timestamp_in_range?(timestamp, date_from, :max), do: timestamp >= date_from
  defp is_timestamp_in_range?(timestamp, date_from, date_to), do: timestamp >= date_from  && timestamp < date_to

  defp maybe_generate_dynamic_periods([%{to: :max} | _], [%{to: :max} = p1, %{to: :max} = p2 | _], timestamp, time_modifier) do
    year = NaiveDateTime.add(~N[0000-01-01 00:00:00], timestamp).year
    [p1, p2]
    |> generate_dynamic_periods(year)
    |> do_find_periods_for_timestamp(timestamp, time_modifier)
  end

  defp maybe_generate_dynamic_periods(found_periods, _periods, _timestamp, _time_modifier) do
    found_periods
  end

  defp naive_datetime_from_iso_days(iso_days) do
    Calendar.ISO.naive_datetime_from_iso_days(iso_days)
    |> (&apply(NaiveDateTime, :new, Tuple.to_list(&1))).()
    |> elem(1)
  end
end
