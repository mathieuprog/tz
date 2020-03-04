defmodule Tz.Compiler do
  @moduledoc false

  require Tz.IanaFileParser
  require Tz.PeriodsBuilder

  alias Tz.PeriodsBuilder
  alias Tz.IanaFileParser

  @reject_time_zone_periods_before_year Application.get_env(:tz, :reject_time_zone_periods_before_year)
  @default_area_name "Misc"

  def compile() do
    tz_data_dir_name =
      File.ls!(:code.priv_dir(:tz))
      |> Enum.filter(&Regex.match?(~r/^tzdata20[0-9]{2}[a-z]$/, &1))
      |> Enum.max()

    periods_and_links =
      for filename <- ~w(africa antarctica asia australasia backward etcetera europe northamerica southamerica)s do
        {zone_records, rule_records, link_records} =
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
              |> PeriodsBuilder.shrink_and_reverse_periods()
              |> PeriodsBuilder.group_periods_by_year()
              |> PeriodsBuilder.reject_time_zone_periods_before_year(@reject_time_zone_periods_before_year)

            {:periods, zone_name, periods}
          end

        links =
          for link <- link_records do
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

    fn_async =
      case :erlang.get(:elixir_compiler_pid) do
        :undefined -> &Task.async/1
        _ -> &Kernel.ParallelCompiler.async/1
      end

    periods_and_links_by_area
    |> Enum.map(&fn_async.(fn -> create_area_module(&1) end))
    |> Enum.each(&Task.await(&1, :infinity))

    contents = [
      quote do
        @moduledoc(false)

        def version() do
          unquote(String.trim(tz_data_dir_name, "tzdata"))
        end
      end,
      for {area, _} <- periods_and_links_by_area, area != @default_area_name do
        module = :"Elixir.Tz.Area.#{area}"
        quote do
          def periods_by_year(unquote(area <> "/") <> rest) do
            apply(unquote(module), :periods_by_year, [unquote(area <> "/") <> rest])
          end
        end
      end,
      quote do
        def periods_by_year(time_zone) do
          apply(unquote(:"Elixir.Tz.Area.#{@default_area_name}"), :periods_by_year, [time_zone])
        end
      end
    ]

    module = :"Elixir.Tz.PeriodsProvider"
    Module.create(module, contents, Macro.Env.location(__ENV__))
    :code.purge(module)
  end

  defp get_time_zone_area(time_zone) do
    case String.split(time_zone, "/") do
      [_] -> nil
      split_time_zone -> hd(split_time_zone)
    end
  end

  defp create_area_module({area, periods_and_links}) do
    contents = [
      quote do
        @moduledoc(false)
      end,
      for period_or_link <- periods_and_links do
        case period_or_link do
          {:link, link_zone_name, canonical_zone_name} ->
            area = get_time_zone_area(canonical_zone_name)
            canonical_module = :"Elixir.Tz.Area.#{area}"

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

    module = :"Elixir.Tz.Area.#{area}"

    Module.create(module, contents, Macro.Env.location(__ENV__))
    :code.purge(module)
  end
end
