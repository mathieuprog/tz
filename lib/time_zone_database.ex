defmodule Tz.TimeZoneDatabase do
  @moduledoc false

  @behaviour Calendar.TimeZoneDatabase

  alias Tz.FileParser.ZoneRuleParser
  alias Tz.PeriodsGenerator.PeriodsBuilder
  alias Tz.PeriodsGenerator.PeriodsProvider
  alias Tz.PeriodsGenerator.Helper

  @impl true
  def time_zone_period_from_utc_iso_days(iso_days, time_zone) do
    with {:ok, periods_by_year} <- PeriodsProvider.periods_by_year(time_zone) do
      naive_datetime = naive_datetime_from_iso_days(iso_days)
      utc_gregorian_seconds = NaiveDateTime.diff(naive_datetime, ~N[0000-01-01 00:00:00])

      found_periods =
        Map.get(periods_by_year, naive_datetime.year, periods_by_year.other)
        |> find_periods_for_timestamp(utc_gregorian_seconds, :utc_gregorian_seconds)

      case Enum.count(found_periods) do
        1 ->
          {:ok, List.first(found_periods)}
        count ->
          raise "#{count} periods found"
      end
    end
  end

  @impl true
  def time_zone_periods_from_wall_datetime(naive_datetime, time_zone) do
    with {:ok, periods_by_year} <- PeriodsProvider.periods_by_year(time_zone) do
      wall_gregorian_seconds = NaiveDateTime.diff(naive_datetime, ~N[0000-01-01 00:00:00])

      found_periods =
        Map.get(periods_by_year, naive_datetime.year, periods_by_year.other)
        |> find_periods_for_timestamp(wall_gregorian_seconds, :wall_gregorian_seconds)

      case Enum.count(found_periods) do
        1 ->
          period = List.first(found_periods)
          case period do
            %{zone_abbr: _} ->
              {:ok, period}
            %{period_before_gap: _} ->
              {:gap, {period.period_before_gap, period.from.wall}, {period.period_after_gap, period.to.wall}}
          end
        3 ->
          {:ambiguous, Enum.at(found_periods, 0), Enum.at(found_periods, 2)}
        count ->
          raise "#{count} periods found"
      end
    end
  end

  defp generate_dynamic_periods([period1, period2], year) do
    rule1 =
      period1.raw_rule
      |> Map.put(:from_year, "#{year - 1}")
      |> Map.put(:to_year, "#{year + 1}")
      |> ZoneRuleParser.transform_rule()

    rule2 =
      period2.raw_rule
      |> Map.put(:from_year, "#{year - 1}")
      |> Map.put(:to_year, "#{year + 1}")
      |> ZoneRuleParser.transform_rule()

    rule_records =
      (rule1 ++ rule2)
      |> Enum.group_by(& &1.name)
      |> (fn rules_by_name ->
        rules_by_name
        |> Enum.map(fn {rule_name, rules} -> {rule_name, Helper.denormalize_rules(rules)} end)
        |> Enum.into(%{})
      end).()

    PeriodsBuilder.build_periods([period1.zone_line], rule_records)
    |> PeriodsBuilder.shrink_and_reverse_periods()
  end

  defp find_periods_for_timestamp(periods, timestamp, time_modifier) do
    do_find_periods_for_timestamp(periods, timestamp, time_modifier)
    |> maybe_generate_dynamic_periods(periods, timestamp, time_modifier)
  end

  defp do_find_periods_for_timestamp(periods, timestamp, time_modifier, periods_found \\ [])

  defp do_find_periods_for_timestamp([], _timestamp, _, periods_found), do: periods_found

  defp do_find_periods_for_timestamp([period | rest_periods], timestamp, time_modifier, periods_found) do
    period_from = if(period.from == :min, do: :min, else: period.from[time_modifier])
    period_to = if(period.to == :max, do: :max, else: period.to[time_modifier])

    periods_found =
      if is_timestamp_in_range?(timestamp, period_from, period_to) do
        [period | periods_found]
      else
        periods_found
      end

    if is_timestamp_after_or_equal_date?(timestamp - 86400, period_from) do
      periods_found
    else
      do_find_periods_for_timestamp(rest_periods, timestamp, time_modifier, periods_found)
    end
  end

  defp is_timestamp_after_or_equal_date?(_, :min), do: true
  defp is_timestamp_after_or_equal_date?(_, :max), do: false
  defp is_timestamp_after_or_equal_date?(timestamp, date), do: timestamp >= date

  defp is_timestamp_in_range?(_, :min, :max), do: true
  defp is_timestamp_in_range?(timestamp, :min, date_to), do: timestamp < date_to
  defp is_timestamp_in_range?(timestamp, date_from, :max), do: timestamp >= date_from
  defp is_timestamp_in_range?(timestamp, date_from, date_to), do: timestamp >= date_from  && timestamp < date_to

  defp maybe_generate_dynamic_periods(found_periods, periods, timestamp, time_modifier) do
    if Enum.any?(found_periods, & &1.to == :max) do
      two_first_periods = Enum.take(periods, 2)

      if Enum.count(two_first_periods, & &1.to == :max) == 2 do
        year = NaiveDateTime.add(~N[0000-01-01 00:00:00], timestamp).year
        two_first_periods
        |> generate_dynamic_periods(year)
        |> do_find_periods_for_timestamp(timestamp, time_modifier)
      else
        found_periods
      end
    else
      found_periods
    end
  end

  defp naive_datetime_from_iso_days(iso_days) do
    Calendar.ISO.naive_datetime_from_iso_days(iso_days)
    |> (&apply(NaiveDateTime, :new, Tuple.to_list(&1))).()
    |> elem(1)
  end
end
