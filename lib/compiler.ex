defmodule Tz.Compiler do
  @moduledoc false

  require Tz.IanaFileParser
  require Tz.PeriodsBuilder

  alias Tz.PeriodsBuilder
  alias Tz.IanaFileParser

  @reject_periods_before_year Application.get_env(:tz, :reject_time_zone_periods_before_year)

  def compile() do
    tz_data_dir_name =
      File.ls!(:code.priv_dir(:tz))
      |> Enum.filter(&Regex.match?(~r/^tzdata20[0-9]{2}[a-z]$/, &1))
      |> Enum.max()

    {periods_and_links, ongoing_rules} =
      for filename <- ~w(africa antarctica asia australasia backward etcetera europe northamerica southamerica)s do
        {zone_records, rule_records, link_records, ongoing_rules} =
          IanaFileParser.parse(Path.join([:code.priv_dir(:tz), tz_data_dir_name, filename]))

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
              |> PeriodsBuilder.periods_to_tuples_and_reverse()
              |> reject_periods_before_year(@reject_periods_before_year)

            {:periods, zone_name, periods}
          end

        links =
          for link <- link_records do
            {:link, link.link_zone_name, link.canonical_zone_name}
          end

        {periods ++ links, ongoing_rules}
      end
      |> Enum.reduce(
          {[], %{}},
          fn {periods_and_links, ongoing_rules}, {all_periods_and_links, all_ongoing_rules} ->
            {periods_and_links ++ all_periods_and_links, Map.merge(ongoing_rules, all_ongoing_rules)}
          end)

    compile_periods(periods_and_links, tz_data_dir_name)

    compile_map_ongoing_changing_rules(ongoing_rules)
  end

  defp reject_periods_before_year(periods, nil), do: periods

  defp reject_periods_before_year(periods, reject_before_year) do
    Enum.reject(periods, fn {secs, _, _, _} ->
      %{year: year} = gregorian_seconds_to_naive_datetime(secs)
      year < reject_before_year
    end)
  end

  defp gregorian_seconds_to_naive_datetime(seconds) do
    :calendar.gregorian_seconds_to_datetime(seconds)
    |> NaiveDateTime.from_erl!()
  end

  def compile_periods(periods_and_links, tz_data_dir_name) do
    quoted = [
      quote do
        @moduledoc(false)

        def version() do
          unquote(String.trim(tz_data_dir_name, "tzdata"))
        end
      end,
      for period_or_link <- periods_and_links do
        case period_or_link do
          {:link, link_zone_name, canonical_zone_name} ->
            quote do
              def periods(unquote(link_zone_name)) do
                periods(unquote(Macro.escape(canonical_zone_name)))
              end
            end
          {:periods, zone_name, periods} ->
            quote do
              def periods(unquote(zone_name)) do
                {:ok, unquote(Macro.escape(periods))}
              end
            end
        end
      end,
      quote do
        def periods(_) do
          {:error, :time_zone_not_found}
        end
      end
    ]

    module = :"Elixir.Tz.PeriodsProvider"
    Module.create(module, quoted, Macro.Env.location(__ENV__))
    :code.purge(module)
  end

  defp compile_map_ongoing_changing_rules(ongoing_rules) do
    quoted = [
      quote do
        @moduledoc(false)
      end,
      for {rule_name, rules} <- ongoing_rules do
        quote do
          def rules(unquote(rule_name)) do
            unquote(Macro.escape(rules))
          end
        end
      end
    ]

    module = :"Elixir.Tz.OngoingChangingRulesProvider"
    Module.create(module, quoted, Macro.Env.location(__ENV__))
    :code.purge(module)
  end
end
