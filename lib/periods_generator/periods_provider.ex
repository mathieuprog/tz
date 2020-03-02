defmodule Tz.PeriodsGenerator.PeriodsProvider do
  @moduledoc false

  require Tz.FileParser.ZoneRuleParser
  require Tz.PeriodsGenerator.PeriodsBuilder

  import Tz.PeriodsGenerator.Helper

  alias Tz.PeriodsGenerator.PeriodsBuilder
  alias Tz.FileParser.ZoneRuleParser

  @iana_tz_version "tzdata2019c"
  @path_to_tz_data_dir Path.join(:code.priv_dir(:tz), @iana_tz_version)
  # @skip_time_zone_periods_before_year Application.get_env(:tz, :skip_time_zone_periods_before_year)
  @build_periods_with_ongoing_dst_changes_until_year Application.get_env(:tz, :build_periods_with_ongoing_dst_changes_until_year, 5 + NaiveDateTime.utc_now().year)
  @default_area_name "Misc"

  def version(), do: @iana_tz_version

  periods_and_links =
    for filename <- ~w(africa antarctica asia australasia backward etcetera europe northamerica southamerica)s do
      records = ZoneRuleParser.parse(Path.join(@path_to_tz_data_dir, filename))

      zone_records =
        Enum.filter(records, & &1.record_type == :zone)
        |> Enum.group_by(& &1.name)
        |> (fn zones_by_name ->
          Enum.map(zones_by_name, fn {zone_name, zone_lines} -> {zone_name, denormalize_zone_lines(zone_lines)} end)
          |> Enum.into(%{})
        end).()

      rule_records =
        Enum.filter(records, & &1.record_type == :rule)
        |> Enum.group_by(& &1.name)
        |> (fn rules_by_name ->
          rules_by_name
          |> Enum.map(fn {rule_name, rules} -> {rule_name, denormalize_rules(rules, @build_periods_with_ongoing_dst_changes_until_year)} end)
          |> Enum.into(%{})
        end).()

      Enum.each(rule_records, fn {rule_name, rules} ->
        ongoing_rules_count = Enum.count(rules, & &1.to == :max)
        if ongoing_rules_count > 2 do
          raise "unexpected case: #{ongoing_rules_count} ongoing rules for rule \"#{rule_name}\""
        end
      end)

      periods =
        for {zone_name, zone_lines} <- zone_records do
          periods =
            PeriodsBuilder.build_periods(zone_lines, rule_records)
            |> PeriodsBuilder.shrink_and_reverse_periods()
            |> PeriodsBuilder.group_periods_by_year()

          {:periods, zone_name, periods}
        end

      links =
        for link <- Enum.filter(records, & &1.record_type == :link) do
          {:link, link.link_zone_name, link.canonical_zone_name}
        end

      periods ++ links
    end
    |> List.flatten()

  periods_and_links_by_area =
    Enum.group_by(periods_and_links, fn
      {:link, link_zone_name, _} -> get_time_zone_area(link_zone_name) || @default_area_name
      {:periods, zone_name, _} -> get_time_zone_area(zone_name) || @default_area_name
    end)

  periods_and_links_by_area
  |> Enum.map(&Kernel.ParallelCompiler.async(fn -> create_area_module(&1, @iana_tz_version) end))
  |> Enum.each(&Task.await(&1, :infinity))

  for {area, _} <- periods_and_links_by_area, area != @default_area_name do
    module = :"Elixir.Tz.Periods.#{area}#{@iana_tz_version}"
    def periods_by_year(unquote(area <> "/") <> rest) do
      apply(unquote(module), :periods_by_year, [unquote(area <> "/") <> rest])
    end
  end

  module = :"Elixir.Tz.Periods.#{@default_area_name}#{@iana_tz_version}"
  def periods_by_year(time_zone) do
    apply(unquote(module), :periods_by_year, [time_zone])
  end
end
