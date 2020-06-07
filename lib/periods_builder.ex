defmodule Tz.PeriodsBuilder do
  @moduledoc false

  def build_periods(zone_lines, rule_records, mode \\ :compilation, prev_period \\ nil, periods \\ [])

  def build_periods([], _rule_records, _mode, _prev_period, periods), do: Enum.reverse(periods)

  def build_periods([zone_line | rest_zone_lines], rule_records, mode, prev_period, periods) do
    rules = Map.get(rule_records, zone_line.rules, zone_line.rules)

    periods =
      build_periods_for_zone_line(zone_line, rules, mode, prev_period)
      |> concat_dedup_periods(periods)

    build_periods(rest_zone_lines, rule_records, mode, hd(periods), periods)
  end

  defp concat_dedup_periods(periods, []), do: periods

  defp concat_dedup_periods(periods1, [first_period2 | tail_period2] = periods2) do
    last_period1 = List.last(periods1)
    compare_keys = [:std_offset_from_utc_time, :local_offset_from_std_time, :zone_abbr]

    cond do
      Map.take(last_period1, compare_keys) == Map.take(first_period2, compare_keys) ->
        (periods1 |> Enum.reverse() |> tl() |> Enum.reverse())
        ++ [%{first_period2 | to: last_period1.to} | tail_period2]

      true ->
        periods1 ++ periods2
    end
  end

  defp offset_diff_from_prev_period(_zone_line, _local_offset, nil), do: 0
  defp offset_diff_from_prev_period(zone_line, local_offset, prev_period) do
    total_offset = zone_line.std_offset_from_utc_time + local_offset
    prev_total_offset = prev_period.std_offset_from_utc_time + prev_period.local_offset_from_std_time
    total_offset - prev_total_offset
  end

  defp build_periods_for_zone_line(zone_line, offset, _mode, prev_period) when is_integer(offset) do
    if zone_line.from != :min && prev_period != nil do
      {zone_from, zone_from_modifier} = zone_line.from
      if prev_period.to[zone_from_modifier] != zone_from do
        raise "logic error"
      end
    end

    offset_diff = offset_diff_from_prev_period(zone_line, offset, prev_period)

    period_from =
      if zone_line.from == :min do
        :min
      else
        add_to_and_convert_date_tuple({prev_period.to.wall, :wall}, offset_diff, zone_line.std_offset_from_utc_time, offset)
      end

    [%{
      from: period_from,
      to: convert_date_tuple(zone_line.to, zone_line.std_offset_from_utc_time, offset),
      std_offset_from_utc_time: zone_line.std_offset_from_utc_time,
      local_offset_from_std_time: offset,
      zone_abbr: zone_abbr(zone_line, offset)
    }]
  end

  defp build_periods_for_zone_line(zone_line, rules, mode, prev_period) when is_list(rules) do
    if zone_line.from != :min && prev_period != nil do
      {zone_from, zone_from_modifier} = zone_line.from
      if prev_period.to[zone_from_modifier] != zone_from do
        raise "logic error"
      end
    end

    if mode == :dynamic_far_future do
      rules
    else
      rules
      |> filter_rules_for_zone_line(zone_line, prev_period, if(prev_period == nil, do: 0, else: prev_period.local_offset_from_std_time))
      |> maybe_pad_left_rule(zone_line, prev_period)
      |> trim_zone_rules(zone_line, prev_period)
    end
    |> do_build_periods_for_zone_line(zone_line, prev_period, [])
  end

  defp filter_rules_for_zone_line(rules, zone_line, prev_period, prev_local_offset_from_std_time, filtered_rules \\ [])
  defp filter_rules_for_zone_line(rules, %{from: :min, to: :max}, _, _, _), do: rules
  defp filter_rules_for_zone_line([], _zone_line, _, _, filtered_rules), do: Enum.reverse(filtered_rules)
  defp filter_rules_for_zone_line([rule | rest_rules], zone_line, prev_period, prev_local_offset_from_std_time, filtered_rules) do
    is_rule_included =
      cond do
        zone_line.to == :max && rule.to == :max ->
          true

        zone_line.to == :max ->
          {rule_to, rule_to_modifier} = rule.to
          prev_period == nil || NaiveDateTime.compare(prev_period.to[rule_to_modifier], rule_to) == :lt

        zone_line.from == :min || rule.to == :max ->
          {zone_to, zone_to_modifier} = zone_line.to
          rule_from = convert_date_tuple(rule.from, prev_period.std_offset_from_utc_time, prev_local_offset_from_std_time)

          NaiveDateTime.compare(zone_to, rule_from[zone_to_modifier]) == :gt

        true ->
          {zone_to, zone_to_modifier} = zone_line.to
          {rule_to, rule_to_modifier} = rule.to
          rule_from = convert_date_tuple(rule.from, prev_period.std_offset_from_utc_time, prev_local_offset_from_std_time)

          NaiveDateTime.compare(prev_period.to[rule_to_modifier], rule_to) == :lt
          && NaiveDateTime.compare(zone_to, rule_from[zone_to_modifier]) == :gt
      end

    if is_rule_included do
      filter_rules_for_zone_line(rest_rules, zone_line, prev_period, rule.local_offset_from_std_time, [rule | filtered_rules])
    else
      filter_rules_for_zone_line(rest_rules, zone_line, prev_period, prev_local_offset_from_std_time, filtered_rules)
    end
  end

  defp trim_zone_rules([], _zone_line, _), do: []
  defp trim_zone_rules([first_rule | tail_rules] = rules, zone_line, prev_period) do
    rules =
      if rule_starts_before_zone_line_range?(zone_line, first_rule, if(prev_period == nil, do: 0, else: prev_period.local_offset_from_std_time)) do
        [%{first_rule | from: zone_line.from} | tail_rules]
      else
        rules
      end

    last_rule = List.last(rules)

    if rule_ends_after_zone_line_range?(zone_line, last_rule) do
      [%{last_rule | to: zone_line.to} | (Enum.reverse(rules) |> tl())]
      |> Enum.reverse()
    else
      rules
    end
  end

  defp rule_starts_before_zone_line_range?(%{from: :min}, _rule, _), do: false
  defp rule_starts_before_zone_line_range?(zone_line, rule, prev_local_offset_from_std_time) do
    rule_from = convert_date_tuple(rule.from, zone_line.std_offset_from_utc_time, prev_local_offset_from_std_time)
    %{from: {zone_from, zone_from_modifier}} = zone_line
    NaiveDateTime.compare(rule_from[zone_from_modifier], zone_from) == :lt
  end

  defp rule_ends_after_zone_line_range?(%{to: :max}, _rule), do: false
  defp rule_ends_after_zone_line_range?(_zone_line, %{to: :max}), do: true
  defp rule_ends_after_zone_line_range?(zone_line, rule) do
    rule_to = convert_date_tuple(rule.to, zone_line.std_offset_from_utc_time, rule.local_offset_from_std_time)
    %{to: {zone_to, zone_to_modifier}} = zone_line
    NaiveDateTime.compare(rule_to[zone_to_modifier], zone_to) == :gt
  end

  defp maybe_pad_left_rule([], _zone_line, _), do: []

  defp maybe_pad_left_rule([first_rule | _] = rules, %{from: :min}, _) do
    rule = %{
      record_type: :rule,
      from: :min,
      name: "",
      local_offset_from_std_time: 0,
      letter: Enum.find(rules, & &1.local_offset_from_std_time == 0).letter,
      to: first_rule.from
    }
    [rule | rules]
  end

  defp maybe_pad_left_rule(rules, _zone_line, nil), do: rules

  defp maybe_pad_left_rule([first_rule | _] = rules, zone_line, prev_period) do
    {rule_from, rule_from_modifier} = first_rule.from

    if NaiveDateTime.compare(prev_period.to[rule_from_modifier], rule_from) == :lt do
      letter =
        # find first rule with local offset to 0
        case Enum.find(rules, & &1.local_offset_from_std_time == 0) do
          %{letter: letter} -> letter
          _ -> ""
        end

      rule = %{
        record_type: :rule,
        from: zone_line.from,
        name: first_rule.name,
        local_offset_from_std_time: 0,
        letter: letter,
        to: first_rule.from
      }
      [rule | rules]
    else
      rules
    end
  end

  defp do_build_periods_for_zone_line([], _zone_line, _prev_period, periods), do: periods

  defp do_build_periods_for_zone_line([rule | rest_rules], zone_line, prev_period, periods) do
    offset_diff = offset_diff_from_prev_period(zone_line, rule.local_offset_from_std_time, prev_period)

    period_from =
      case prev_period do
        nil ->
          convert_date_tuple(zone_line.from, zone_line.std_offset_from_utc_time, 0)
        %{to: :max} ->
          convert_date_tuple(rule.from, zone_line.std_offset_from_utc_time, prev_period.local_offset_from_std_time)
        _ ->
          add_to_and_convert_date_tuple({prev_period.to.wall, :wall}, offset_diff, zone_line.std_offset_from_utc_time, rule.local_offset_from_std_time)
      end

    period_to = convert_date_tuple(rule.to, zone_line.std_offset_from_utc_time, rule.local_offset_from_std_time)

    if period_from != :min && period_to != :max && period_from.utc_gregorian_seconds == period_to.utc_gregorian_seconds do
      raise "logic error"
    end

    period = %{
      from: period_from,
      to: period_to,
      std_offset_from_utc_time: zone_line.std_offset_from_utc_time,
      local_offset_from_std_time: rule.local_offset_from_std_time,
      zone_abbr: zone_abbr(zone_line, rule.local_offset_from_std_time, rule.letter),
      rules_and_template:
        if(period_to == :max && prev_period && prev_period.to == :max) do
          {zone_line.rules, zone_line.format_time_zone_abbr}
        end
    }

    periods = concat_dedup_periods([period], periods)

    do_build_periods_for_zone_line(rest_rules, zone_line, period, periods)
  end

  defp zone_abbr(zone_line, offset, letter \\ "") do
    is_standard_time = offset == 0

    cond do
      String.contains?(zone_line.format_time_zone_abbr, "/") ->
        [zone_abbr_std_time, zone_abbr_dst_time] = String.split(zone_line.format_time_zone_abbr, "/")
        if(is_standard_time, do: zone_abbr_std_time, else: zone_abbr_dst_time)

      String.contains?(zone_line.format_time_zone_abbr, "%s") ->
        String.replace(zone_line.format_time_zone_abbr, "%s", letter)

      true ->
        zone_line.format_time_zone_abbr
    end
  end

  defp add_to_and_convert_date_tuple(:min, _, _, _), do: :min
  defp add_to_and_convert_date_tuple(:max, _, _, _), do: :max
  defp add_to_and_convert_date_tuple({date, time_modifier}, add_seconds, std_offset_from_utc_time, local_offset_from_std_time) do
    date = NaiveDateTime.add(date, add_seconds, :second)
    convert_date_tuple({date, time_modifier}, std_offset_from_utc_time, local_offset_from_std_time)
  end

  defp convert_date_tuple(:min, _, _), do: :min
  defp convert_date_tuple(:max, _, _), do: :max
  defp convert_date_tuple({date, time_modifier}, std_offset_from_utc_time, local_offset_from_std_time) do
    utc = convert_date(date, std_offset_from_utc_time, local_offset_from_std_time, time_modifier, :utc)
    %{
      utc: utc,
      wall: convert_date(date, std_offset_from_utc_time, local_offset_from_std_time, time_modifier, :wall),
      standard: convert_date(date, std_offset_from_utc_time, local_offset_from_std_time, time_modifier, :standard)
    }
    |> Map.put(:utc_gregorian_seconds, naive_datetime_to_gregorian_seconds(utc))
  end

  def periods_to_tuples_and_reverse(periods, shrank_periods \\ [], prev_period \\ nil)

  def periods_to_tuples_and_reverse([], shrank_periods, _), do: shrank_periods

  def periods_to_tuples_and_reverse([period | tail], shrank_periods, prev_period) do
    period = {
      if(period.from == :min, do: 0, else: period.from.utc_gregorian_seconds),
      {
        period.std_offset_from_utc_time,
        period.local_offset_from_std_time,
        period.zone_abbr
      },
      prev_period && elem(prev_period, 1),
      period[:rules_and_template]
    }

    periods_to_tuples_and_reverse(tail, [period | shrank_periods], period)
  end

  defp convert_date(ndt, _, _, modifier, modifier), do: ndt

  defp convert_date(ndt, standard_offset_from_utc_time, local_offset_from_standard_time, :wall, :utc) do
    NaiveDateTime.add(ndt, -1 * (standard_offset_from_utc_time + local_offset_from_standard_time), :second)
  end

  defp convert_date(ndt, _standard_offset_from_utc_time, local_offset_from_standard_time, :wall, :standard) do
    NaiveDateTime.add(ndt, -1 * local_offset_from_standard_time, :second)
  end

  defp convert_date(ndt, standard_offset_from_utc_time, local_offset_from_standard_time, :utc, :wall) do
    NaiveDateTime.add(ndt, standard_offset_from_utc_time + local_offset_from_standard_time, :second)
  end

  defp convert_date(ndt, standard_offset_from_utc_time, _local_offset_from_standard_time, :utc, :standard) do
    NaiveDateTime.add(ndt, standard_offset_from_utc_time, :second)
  end

  defp convert_date(ndt, standard_offset_from_utc_time, _local_offset_from_standard_time, :standard, :utc) do
    NaiveDateTime.add(ndt, -1 * standard_offset_from_utc_time, :second)
  end

  defp convert_date(ndt, _standard_offset_from_utc_time, local_offset_from_standard_time, :standard, :wall) do
    NaiveDateTime.add(ndt, local_offset_from_standard_time, :second)
  end

  defp naive_datetime_to_gregorian_seconds(datetime) do
    NaiveDateTime.to_erl(datetime)
    |> :calendar.datetime_to_gregorian_seconds()
  end
end
