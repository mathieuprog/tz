defmodule Tz.Compiler do
  @moduledoc false

  require Logger
  require Tz.IanaFileParser
  require Tz.PeriodsBuilder

  alias Tz.IanaDataDir
  alias Tz.IanaFileParser
  alias Tz.PeriodsBuilder

  def compile() do
    {tzdata_dir_path, tzdata_version} = tzdata_dir_and_version()

    {periods_and_links, ongoing_rules} =
      for filename <- ~w(africa antarctica asia australasia backward etcetera europe northamerica southamerica)s do
        {zone_records, rule_records, link_records, ongoing_rules} =
          IanaFileParser.parse(Path.join(tzdata_dir_path, filename))

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
              |> reject_periods_before_year()

            if length(periods) == 0 do
              raise "no periods for time zone #{zone_name}"
            end

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

    compile_periods(periods_and_links, tzdata_version)

    compile_map_ongoing_changing_rules(ongoing_rules)
  end

  defp tzdata_dir_and_version() do
    IanaDataDir.maybe_copy_iana_files_to_custom_dir()

    cond do
      tzdata_dir_path = IanaDataDir.relevant_tzdata_dir_path() ->
        "tzdata" <> tzdata_version = Path.basename(tzdata_dir_path)

        {tzdata_dir_path, tzdata_version}

      IanaDataDir.forced_iana_version() == nil ->
        raise "tzdata files not found"

      tzdata_dir_path = IanaDataDir.latest_tzdata_dir_path() ->
        "tzdata" <> tzdata_version = Path.basename(tzdata_dir_path)

        Logger.warn(
          "Tz is compiling with version #{tzdata_version}. "
          <> "Download version #{IanaDataDir.forced_iana_version()} "
          <> "(run `mix tz.download #{IanaDataDir.forced_iana_version()}`) "
          <> "and compile :tz again "
          <> "(run `mix deps.compile tz --force`).")

        {tzdata_dir_path, tzdata_version}

      true ->
        raise "tzdata files not found"
    end
  end

  defp reject_periods_before_year(periods) do
    case Application.get_env(:tz, :reject_periods_before_year) do
      nil ->
        periods

      reject_before_year ->
        filtered_periods =
          Enum.reject(periods, fn {secs, _, _, _} ->
            %{year: year} = gregorian_seconds_to_naive_datetime(secs)
            year < reject_before_year
          end)

        if length(filtered_periods) > 0 do
          filtered_periods
        else
          periods
        end
    end
  end

  defp gregorian_seconds_to_naive_datetime(seconds) do
    :calendar.gregorian_seconds_to_datetime(seconds)
    |> NaiveDateTime.from_erl!()
  end

  def compile_periods(periods_and_links, tzdata_version) do
    quoted = [
      quote do
        @moduledoc(false)

        def iana_version() do
          unquote(tzdata_version)
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
