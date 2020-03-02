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

  def denormalize_rules(rules, build_periods_with_ongoing_dst_changes_until_year \\ 0) do
    ongoing_switch_rules = Enum.filter(rules, & &1.ongoing_switch)

    rules =
      case length(ongoing_switch_rules) do
        0 ->
          rules
        2 ->
          [rule1, rule2] = ongoing_switch_rules
          last_year = Enum.max([
            build_periods_with_ongoing_dst_changes_until_year,
            elem(rule1.from, 0).year,
            elem(rule2.from, 0).year
          ])

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

  def get_time_zone_area(time_zone) do
    case String.split(time_zone, "/") do
      [_] -> nil
      split_time_zone -> hd(split_time_zone)
    end
  end

  def create_area_module({area, periods_and_links}, iana_tz_version) do
    contents = [
      quote do
        @moduledoc(false)
      end,
      for period_or_link <- periods_and_links do
        case period_or_link do
          {:link, link_zone_name, canonical_zone_name} ->
            area = get_time_zone_area(canonical_zone_name)
            canonical_module = :"Elixir.Tz.Periods.#{area}#{iana_tz_version}"

            quote do
              def periods_by_year(unquote(link_zone_name)) do
                apply(unquote(canonical_module), :periods_by_year, [unquote(canonical_zone_name)])
              end
            end
          {:periods, zone_name, periods_by_year} ->
            quote do
              def periods_by_year(unquote(zone_name)) do
                {:ok, unquote(Macro.escape(periods_by_year))}
              end
            end
        end
      end,
      quote do
        def periods_by_year(_) do
          {:error, :time_zone_not_found}
        end
      end
    ]

    module = :"Elixir.Tz.Periods.#{area}#{iana_tz_version}"
    Module.create(module, contents, Macro.Env.location(__ENV__))
  end
end
