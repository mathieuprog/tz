defmodule Tz.PeriodsGenerator.PeriodsProvider do
  @moduledoc false

  require Tz.PeriodsGenerator.Helper
  require Tz.FileParser.ZoneRuleParser
  require Tz.PeriodsGenerator.PeriodsBuilder

  import Tz.PeriodsGenerator.Helper

  alias Tz.PeriodsGenerator.PeriodsBuilder
  alias Tz.FileParser.ZoneRuleParser

  @iana_tz_version "tzdata2019c"
  @path Path.join(:code.priv_dir(:tz), @iana_tz_version)

  def version(), do: @iana_tz_version

  for filename <- ~w(africa antarctica asia australasia backward etcetera europe northamerica southamerica)s do
    records = ZoneRuleParser.parse(Path.join(@path, filename))

    zone_records =
      Enum.filter(records, & &1.record_type == :zone)
      |> Enum.group_by(& &1.name)
      |> (fn zones_by_name ->
        Enum.map(zones_by_name, fn {zone_name, zone_lines} -> {zone_name, denormalize_zone_lines(zone_lines)} end)
        |> Enum.into(%{})
      end).()

    max_zone_to =
      if zone_records != %{} do
        Enum.flat_map(zone_records, fn {_zone_name, zone_lines} ->
          zone_lines
        end)
        |> Enum.map(fn
          %{to: :max} -> ~N[0000-01-01 00:00:00]
          %{to: {naive_date_time, _}} -> naive_date_time
        end)
        |> Enum.max(NaiveDateTime)
      end

    rule_records =
      Enum.filter(records, & &1.record_type == :rule)
      |> Enum.group_by(& &1.name)
      |> (fn rules_by_name ->
        rules_by_name
        |> Enum.map(fn {rule_name, rules} -> {rule_name, denormalize_rules(rules, max_zone_to)} end)
        |> Enum.into(%{})
      end).()

    Enum.each(rule_records, fn {rule_name, rules} ->
      ongoing_rules_count = Enum.count(rules, & &1.to == :max)
      if ongoing_rules_count > 2 do
        raise "unexpected case: #{ongoing_rules_count} ongoing rules for rule \"#{rule_name}\""
      end
    end)

    for {zone_name, zone_lines} <- zone_records do
      periods =
        PeriodsBuilder.build_periods(zone_lines, rule_records)
        |> PeriodsBuilder.shrink_and_reverse_periods()

      def periods(unquote(zone_name)) do
        {:ok, unquote(Macro.escape(periods))}
      end
    end

    for link <- Enum.filter(records, & &1.record_type == :link) do
      def periods(unquote(link.link_zone_name)) do
        periods(unquote(Macro.escape(link.canonical_zone_name)))
      end
    end
  end

  def periods(_) do
    {:error, :time_zone_not_found}
  end
end
