defmodule Tz.IanaFileParser do
  @moduledoc false
  # https://data.iana.org/time-zones/tzdb/tz-how-to.html

  @build_dst_periods_until_year Application.compile_env(:tz, :build_dst_periods_until_year, 5 + NaiveDateTime.utc_now().year)

  def parse(file_path) do
    records =
      File.stream!(file_path)
      |> strip_comments()
      |> strip_empty()
      |> trim()
      |> Enum.to_list()
      |> parse_strings_into_maps()

    zones = Enum.filter(records, & &1.record_type == :zone)
    rules = Enum.filter(records, & &1.record_type == :rule)
    links = Enum.filter(records, & &1.record_type == :link)

    {
      denormalized_zone_data(zones),
      denormalized_rule_data(rules, @build_dst_periods_until_year),
      links,
      Enum.filter(rules, & &1.ongoing_switch)
      |> Enum.group_by(& &1.name)
    }
  end

  defp strip_comments(stream) do
    stream
    |> Stream.filter(&(!Regex.match?(~r/^[\s]*#/, &1)))
    |> Stream.map(&Regex.replace(~r/[\s]*#.+/, &1, ""))
  end

  defp strip_empty(stream) do
    Stream.filter(stream, &(!Regex.match?(~r/^[\s]*\n$/, &1)))
  end

  defp trim(stream) do
    Stream.map(stream, &String.trim(&1))
  end

  defp parse_strings_into_maps(strings, state \\ %{current_zone_name: nil})

  defp parse_strings_into_maps([], _), do: []

  defp parse_strings_into_maps([string | tail], state) do
    %{current_zone_name: current_zone_name} = state

    {maps, state} =
      cond do
        String.starts_with?(string, "Rule") ->
          {parse_rule_string_into_maps(string), %{current_zone_name: nil}}

        String.starts_with?(string, "Link") ->
          {[parse_link_string_into_map(string)], %{current_zone_name: nil}}

        String.starts_with?(string, "Zone") ->
          zone = parse_zone_string_into_map(string)
          {[zone], %{current_zone_name: zone.name}}

        true ->
          zone = parse_zone_string_into_map(string, current_zone_name)
          {[zone], %{current_zone_name: current_zone_name}}
      end

    maps ++ parse_strings_into_maps(tail, state)
  end

  defp parse_rule_string_into_maps(rule_string) do
    Enum.zip([
      [:name, :from_year, :to_year, :_, :month, :day, :time, :local_offset_from_std_time, :letter],
      tl(String.split(rule_string, ~r{\s}, trim: true, parts: 10))
      |> Enum.map(& String.trim(&1))
    ])
    |> Enum.into(%{})
    |> Map.delete(:_)
    |> Map.put(:record_type, :rule)
    |> transform_rule()
  end

  defp parse_link_string_into_map(link_string) do
    Enum.zip([
      [:canonical_zone_name, :link_zone_name],
      tl(String.split(link_string, ~r{\s}, trim: true, parts: 3))
      |> Enum.map(& String.trim(&1))
    ])
    |> Enum.into(%{})
    |> Map.put(:record_type, :link)
  end

  defp parse_zone_string_into_map(zone_string) do
    Enum.zip([
      [:name, :std_offset_from_utc_time, :rules, :format_time_zone_abbr, :to],
      tl(String.split(zone_string, ~r{\s}, trim: true, parts: 6))
      |> Enum.map(& String.trim(&1))
    ])
    |> Enum.into(%{})
    |> Map.merge(%{to: :max}, fn _k, v1, _v2 -> v1 end)
    |> Map.put(:record_type, :zone)
    |> transform_zone()
  end

  defp parse_zone_string_into_map(zone_string, current_zone_name) do
    Enum.zip([
      [:name, :std_offset_from_utc_time, :rules, :format_time_zone_abbr, :to],
      [
        current_zone_name |
        String.split(zone_string, ~r{\s}, trim: true, parts: 4)
        |> Enum.map(& String.trim(&1))
      ]
    ])
    |> Enum.into(%{})
    |> Map.merge(%{to: :max}, fn _k, v1, _v2 -> v1 end)
    |> Map.put(:record_type, :zone)
    |> transform_zone()
  end

  defp transform_zone(%{} = zone) do
    rules = String.trim(zone.rules)

    rules =
      cond do
        rules == "-" -> 0
        String.match?(rules, ~r/[+-]?[0-9]+/) ->
          offset_string_to_seconds(rules)
        rules -> rules
      end

    std_offset = offset_string_to_seconds(zone.std_offset_from_utc_time)

    %{
      record_type: :zone,
      name: zone.name,
      rules: rules,
      to: parse_to_field_string(zone.to),
      std_offset_from_utc_time: std_offset,
      format_time_zone_abbr: zone.format_time_zone_abbr
    }
  end

  def transform_rule(%{} = rule) do
    {from_year, to_year} = year_strings_to_integers(rule.from_year, rule.to_year)
    month = month_string_to_integer(rule.month)
    {hour, minute, second, time_modifier} = parse_time_string(rule.time)

    {ongoing_switch, to_year} =
      if to_year == :max do
        {true, from_year}
      else
        {false, to_year}
      end

    for year <- Range.new(from_year, to_year) do
      parsed_day = parse_day_string(rule.day)
      {year, month, day} = parsed_day_to_date(year, month, parsed_day)

      naive_date_time = new_naive_date_time(year, month, day, hour, minute, second)

      local_offset = offset_string_to_seconds(rule.local_offset_from_std_time)

      %{
        record_type: :rule,
        from: {naive_date_time, time_modifier},
        ongoing_switch: ongoing_switch,
        name: rule.name,
        local_offset_from_std_time: local_offset,
        letter: if(rule.letter == "-", do: "", else: rule.letter),
        __datetime_data: %{
          date: {year, month, parsed_day},
          time: {hour, minute, second, time_modifier}
        }
      }
    end
  end

  def change_rule_year(rule, year, ongoing_switch \\ false)

  def change_rule_year(%{to: _} = rule, year, ongoing_switch) do
    rule
    |> Map.put(:ongoing_switch, ongoing_switch)
    |> Map.delete(:to)
    |> change_rule_year(year, ongoing_switch)
  end

  def change_rule_year(%{} = rule, year, ongoing_switch) do
    %{
      date: {_, month, parsed_day},
      time: {hour, minute, second, time_modifier}
    } = rule.__datetime_data

    {year, month, day} = parsed_day_to_date(year, month, parsed_day)
    naive_date_time = new_naive_date_time(year, month, day, hour, minute, second)

    %{rule |
      from: {naive_date_time, time_modifier},
      ongoing_switch: ongoing_switch
    }
  end

  defp new_naive_date_time(year, month, day, 24, minute, second) do
    {:ok, naive_date_time} = NaiveDateTime.new(year, month, day, 0, minute, second)
    NaiveDateTime.add(naive_date_time, 86400)
  end

  defp new_naive_date_time(year, month, day, 25, minute, second) do
    {:ok, naive_date_time} = NaiveDateTime.new(year, month, day, 1, minute, second)
    NaiveDateTime.add(naive_date_time, 86400)
  end

  defp new_naive_date_time(year, month, day, hour, minute, second) do
    {:ok, naive_date_time} = NaiveDateTime.new(year, month, day, hour, minute, second)
    naive_date_time
  end

  defp parse_day_string(day_string) do
    cond do
      String.contains?(day_string, "last") ->
        "last" <> day_of_week_string = day_string
        day_of_week = day_of_week_string_to_integer(day_of_week_string)
        {:last_dow, day_of_week}
      String.contains?(day_string, "<=") ->
        [day_of_week_string, on_or_before_day] = String.split(day_string, "<=", trim: true)
        day_of_week = day_of_week_string_to_integer(day_of_week_string)
        on_or_before_day = String.to_integer(on_or_before_day)
        {:dow_equal_or_before_day, day_of_week, on_or_before_day}
      String.contains?(day_string, ">=") ->
        [day_of_week_string, on_or_after_day] = String.split(day_string, ">=", trim: true)
        day_of_week = day_of_week_string_to_integer(day_of_week_string)
        on_or_after_day = String.to_integer(on_or_after_day)
        {:dow_equal_or_after_day, day_of_week, on_or_after_day}
      String.match?(day_string, ~r/[0-9]+/) ->
        {:day, String.to_integer(day_string)}
      true ->
        raise "could not parse day from rule (day to parse is \"#{day_string}\")"
    end
  end

  defp parsed_day_to_date(year, month, parsed_day) do
    case parsed_day do
      {:last_dow, day_of_week} ->
        day = day_at_last_given_day_of_week_of_month(year, month, day_of_week)
        {year, month, day}
      {:dow_equal_or_before_day, day_of_week, on_or_before_day} ->
        day_at_given_day_of_week_of_month(year, month, day_of_week, :on_or_before_day, on_or_before_day)
      {:dow_equal_or_after_day, day_of_week, on_or_after_day} ->
        day_at_given_day_of_week_of_month(year, month, day_of_week, :on_or_after_day, on_or_after_day)
      {:day, day} ->
        {year, month, day}
    end
  end

  defp parse_to_field_string(:min), do: :min
  defp parse_to_field_string(:max), do: :max
  defp parse_to_field_string(to_field_string) do
    {year, month, day, hour, minute, second, time_modifier} =
      case String.split(to_field_string) do
        [year, month, day, time] ->
          year = String.to_integer(year)
          month = month_string_to_integer(month)
          parsed_day = parse_day_string(day)
          {year, month, day} = parsed_day_to_date(year, month, parsed_day)

          {hour, minute, second, time_modifier} = parse_time_string(time)
          {year, month, day, hour, minute, second, time_modifier}
        [year, month, day] ->
          year = String.to_integer(year)
          month = month_string_to_integer(month)
          parsed_day = parse_day_string(day)
          {year, month, day} = parsed_day_to_date(year, month, parsed_day)

          {year, month, day, 0, 0, 0, :wall}
        [year, month] ->
          year = String.to_integer(year)
          month = month_string_to_integer(month)

          {year, month, 1, 0, 0, 0, :wall}
        [year] ->
          year = String.to_integer(year)

          {year, 1, 1, 0, 0, 0, :wall}
       end

    naive_date_time = new_naive_date_time(year, month, day, hour, minute, second)
    {naive_date_time, time_modifier}
  end

  defp day_at_given_day_of_week_of_month(year, month, day_of_week, :on_or_before_day, on_or_before_day) do
    {:ok, on_or_before_date} = Date.new(year, month, on_or_before_day)

    days_to_subtract = diff_days_of_week(day_of_week, Date.day_of_week(on_or_before_date))
    date = Date.add(on_or_before_date, -1 * days_to_subtract)

    {date.year, date.month, date.day}
  end

  defp day_at_given_day_of_week_of_month(year, month, day_of_week, :on_or_after_day, on_or_after_day) do
    {:ok, on_or_after_date} = Date.new(year, month, on_or_after_day)

    days_to_add = diff_days_of_week(Date.day_of_week(on_or_after_date), day_of_week)
    date = Date.add(on_or_after_date, days_to_add)

    {date.year, date.month, date.day}
  end

  defp day_at_last_given_day_of_week_of_month(year, month, day_of_week) do
    date_at_end_of_month = date_at_end_of_month(year, month)
    days_to_subtract = diff_days_of_week(day_of_week, Date.day_of_week(date_at_end_of_month))
    date = Date.add(date_at_end_of_month, -1 * days_to_subtract)
    date.day
  end

  defp diff_days_of_week(from_day_of_week, to_day_of_week) do
    rem(7 + (to_day_of_week - from_day_of_week), 7)
  end

  defp date_at_end_of_month(year, month) do
    {:ok, date} = Date.new(year, month, 1)
    last_day = Date.days_in_month(date)
    {:ok, date} = Date.new(year, month, last_day)
    date
  end

  defp year_strings_to_integers(from_year, "only") do
    {String.to_integer(from_year), String.to_integer(from_year)}
  end

  defp year_strings_to_integers(from_year, "max") do
    {String.to_integer(from_year), :max}
  end

  defp year_strings_to_integers(from_year, to_year) do
    {String.to_integer(from_year), String.to_integer(to_year)}
  end

  defp month_string_to_integer(month_string) do
    month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    1 + Enum.find_index(month_names, &month_string == &1)
  end

  defp day_of_week_string_to_integer(day_of_week_string) do
    day_of_week_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    1 + Enum.find_index(day_of_week_names, &day_of_week_string == &1)
  end

  defp parse_time_string(time_string) do
    {hour, minute, second, time_modifier} =
      String.split(time_string, ~r{[:gsuz]}, include_captures: true, trim: true)
      |> case do
         [hour, ":", minute, ":", second, time_modifier] when time_modifier in ["g", "u", "z"] ->
           {hour, minute, second, :utc}
         [hour, ":", minute, time_modifier] when time_modifier in ["g", "u", "z"] ->
           {hour, minute, "0", :utc}
         [hour, ":", minute, ":", second, time_modifier] when time_modifier == "s" ->
           {hour, minute, second, :standard}
         [hour, ":", minute, time_modifier] when time_modifier == "s" ->
           {hour, minute, "0", :standard}
         [hour, ":", minute, ":", second] ->
           {hour, minute, second, :wall}
         [hour, ":", minute] ->
           {hour, minute, "0", :wall}
         _ ->
           raise "could not parse time string \"#{time_string}\""
       end

    hour = String.to_integer(hour)
    minute = String.to_integer(minute)
    second = String.to_integer(second)

    {hour, minute, second, time_modifier}
  end

  defp offset_string_to_seconds(offset_string) do
    {is_negative, hours, minutes, seconds} =
      String.split(offset_string, ~r{[:\-]}, include_captures: true, trim: true)
      |> case do
        ["-", hours, ":", minutes, ":", seconds] ->
          {true, hours, minutes, seconds}
        ["-", hours, ":", minutes] ->
          {true, hours, minutes, "0"}
        [hours, ":", minutes, ":", seconds] ->
          {false, hours, minutes, seconds}
        [hours, ":", minutes] ->
          {false, hours, minutes, "0"}
        ["-", hours] ->
          {true, hours, "0", "0"}
        [hours] ->
          {false, hours, "0", "0"}
        _ ->
          raise "could not parse time string \"#{offset_string}\""
      end

    hours = String.to_integer(hours)
    minutes = String.to_integer(minutes)
    seconds = String.to_integer(seconds)

    total_seconds = hours * 3600 + minutes * 60 + seconds

    if(is_negative, do: -1 * total_seconds, else: total_seconds)
  end

  defp denormalized_zone_data(zone_records) do
    zone_records
    |> Enum.group_by(& &1.name)
    |> (fn zones_by_name ->
      Enum.map(zones_by_name, fn {zone_name, zone_lines} -> {zone_name, denormalize_zone_lines(zone_lines)} end)
      |> Enum.into(%{})
    end).()
  end

  def denormalized_rule_data(rule_records, build_dst_periods_until_year \\ 0) do
    rule_records
    |> Enum.group_by(& &1.name)
    |> (fn rules_by_name ->
      rules_by_name
      |> Enum.map(fn {rule_name, rules} -> {rule_name, denormalize_rules(rules, build_dst_periods_until_year)} end)
      |> Enum.into(%{})
    end).()
  end

  defp denormalize_zone_lines(zone_lines) do
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

  defp denormalize_rules(rules, build_dst_periods_until_year) do
    ongoing_switch_rules = Enum.filter(rules, & &1.ongoing_switch)

    rules =
      case ongoing_switch_rules do
        [] ->
          rules
        [rule1, rule2] ->
          last_year = Enum.max([
            build_dst_periods_until_year,
            elem(List.last(rules).from, 0).year,
            elem(rule1.from, 0).year,
            elem(rule2.from, 0).year
          ])

          Enum.filter(rules, & !&1.ongoing_switch)
          ++ for year <- Range.new(elem(rule1.from, 0).year, last_year) do
               change_rule_year(rule1, year)
             end
          ++ [change_rule_year(rule1, last_year + 1, true)]
          ++ for year <- Range.new(elem(rule2.from, 0).year, last_year) do
               change_rule_year(rule2, year)
             end
          ++ [change_rule_year(rule2, last_year + 1, true)]
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
