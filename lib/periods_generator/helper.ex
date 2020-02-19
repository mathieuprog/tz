defmodule Tz.PeriodsGenerator.Helper do
  @moduledoc false

  require Tz.FileParser.ZoneRuleParser
  alias Tz.FileParser.ZoneRuleParser

  def convert_date(naive_date_time, _standard_offset_from_utc_time, _local_offset_from_standard_time, :wall, :wall), do: naive_date_time
  def convert_date(naive_date_time, _standard_offset_from_utc_time, _local_offset_from_standard_time, :utc, :utc), do: naive_date_time
  def convert_date(naive_date_time, _standard_offset_from_utc_time, _local_offset_from_standard_time, :standard, :standard), do: naive_date_time
  def convert_date(naive_date_time, standard_offset_from_utc_time, local_offset_from_standard_time, :wall, :utc) do
    NaiveDateTime.add(naive_date_time, -1 * (standard_offset_from_utc_time + local_offset_from_standard_time), :second)
  end
  def convert_date(naive_date_time, _standard_offset_from_utc_time, local_offset_from_standard_time, :wall, :standard) do
    NaiveDateTime.add(naive_date_time, -1 * local_offset_from_standard_time, :second)
  end
  def convert_date(naive_date_time, standard_offset_from_utc_time, local_offset_from_standard_time, :utc, :wall) do
    NaiveDateTime.add(naive_date_time, standard_offset_from_utc_time + local_offset_from_standard_time, :second)
  end
  def convert_date(naive_date_time, standard_offset_from_utc_time, _local_offset_from_standard_time, :utc, :standard) do
    NaiveDateTime.add(naive_date_time, standard_offset_from_utc_time, :second)
  end
  def convert_date(naive_date_time, standard_offset_from_utc_time, _local_offset_from_standard_time, :standard, :utc) do
    NaiveDateTime.add(naive_date_time, -1 * standard_offset_from_utc_time, :second)
  end
  def convert_date(naive_date_time, _standard_offset_from_utc_time, local_offset_from_standard_time, :standard, :wall) do
    NaiveDateTime.add(naive_date_time, local_offset_from_standard_time, :second)
  end

  def denormalize_zone_lines(zone_lines) do
    zone_lines
    |> Enum.with_index()
    |> Enum.map(fn {zone_line, index} ->
      Map.put(zone_line, :from,
        cond do
          index == 0 -> :min
          true -> Enum.at(zone_lines, index - 1).to
        end)
    end)
  end

  def denormalize_rules(rules, min_date_until \\ ~N[0000-01-01 00:00:00])

  def denormalize_rules(rules, min_date_until) do
    ongoing_switch_rules = Enum.filter(rules, & &1.ongoing_switch)

    rules =
      case length(ongoing_switch_rules) do
        0 ->
          rules
        2 ->
          [rule1, rule2] = ongoing_switch_rules
          last_year = Enum.max([elem(rule1.from, 0), elem(rule2.from, 0), min_date_until], NaiveDateTime).year

          Enum.filter(rules, & !&1.ongoing_switch)
          ++ (rule1.raw
              |> Map.put(:to_year, "#{last_year}")
              |> ZoneRuleParser.transform_rule())
          ++ (rule1.raw
              |> Map.put(:from_year, "#{last_year + 1}")
              |> Map.put(:to_year, "max")
              |> ZoneRuleParser.transform_rule())
          ++ (rule2.raw
              |> Map.put(:to_year, "#{last_year}")
              |> ZoneRuleParser.transform_rule())
          ++ (rule2.raw
              |> Map.put(:from_year, "#{last_year + 1}")
              |> Map.put(:to_year, "max")
              |> ZoneRuleParser.transform_rule())
        _ ->
          raise "unexpected number of rules to \"max\", rules: \"#{inspect rules}\""
      end

    rules =
      Enum.sort(rules, fn rule1, rule2 ->
        naive_date_time1 = elem(rule1.from, 0)
        time_modifier1 = elem(rule1.from, 1)
        naive_date_time2 = elem(rule2.from, 0)
        time_modifier2 = elem(rule2.from, 1)

        diff = NaiveDateTime.diff(naive_date_time1, naive_date_time2)

        if (abs(diff) < 86400 && time_modifier1 != time_modifier2) do
          raise "unexpected case"
        end

        diff < 0
      end)

    rules
    |> Enum.with_index()
    |> Enum.map(fn {rule, index} ->
      rule
      |> Map.put(:to,
        if rule.ongoing_switch do
          :max
        else
          case Enum.at(rules, index + 1, nil) do
            nil -> :max
            next_rule -> next_rule.from
          end
        end)
      |> Map.delete(:ongoing_switch)
    end)
  end
end
