# Tz

Time zone support for Elixir.

The Elixir standard library does not ship with a time zone database. As a result, the functions in the `DateTime`
module can, by default, only operate on datetimes in the UTC time zone. Alternatively (and
[deliberately](https://elixirforum.com/t/14743)), the standard library relies on
third-party libraries, such as `tz`, to bring in time zone support and deal with datetimes in other time zones than UTC.

The `tz` library relies on the [time zone database](https://data.iana.org/time-zones/tzdb/) maintained by
[IANA](https://www.iana.org). As of version 0.22.0, `tz` uses version **tzdata2022c** of the IANA time zone database.

## Features

### Battle-tested

The `tz` library is tested against nearly 10 million past dates, which includes most of all possible imaginable
edge cases.

### Pre-compiled time zone data

Time zone periods are deducted from the [IANA time zone data](https://data.iana.org/time-zones/tzdb/). A period is a
period of time where a certain offset is observed. Example: in Belgium, from 31 March 2019 until 27 October 2019, clock
went forward by 1 hour; this means that during this period, Belgium observed a total offset of 2 hours from UTC time.

The time zone periods are computed and made available in Elixir maps during compilation time, to be consumed by the
[DateTime](https://hexdocs.pm/elixir/DateTime.html#module-time-zone-database) module.

### Automatic time zone data updates

`tz` can watch for IANA time zone database updates and automatically recompile the time zone periods.

To enable automatic updates, add `Tz.UpdatePeriodically` as a child in your supervisor:

```elixir
{Tz.UpdatePeriodically, []}
```

You may pass the option `:interval_in_days` in order to configure the frequency of the task.

```elixir
{Tz.UpdatePeriodically, [interval_in_days: 5]}
```

If you do not wish to update automatically, but still wish to be alerted for new upcoming IANA updates, add
`Tz.WatchPeriodically` as a child in your supervisor:

```elixir
{Tz.WatchPeriodically, []}
```

You may pass the options:
* `:interval_in_days`: frequency of the task
* `:on_update`: a callback executed when an update is available

This will simply log to your server when a new time zone database is available.

Some users prefer to watch and update manually. Example cases:

* Dealing with memory limitations: some embedded devices may not afford to recompile the time zone data at runtime.
* Restricted environments: the request may be blocked because of security policies.
* Security concerns: some users may prefer to analyze the files coming from external sources (`data.iana.org` in this case) before processing.
* Systems interoperability: some other systems may use other versions of the IANA database.

For updating manually, there are two options:

* just update the `tz` library which hopefully includes the latest IANA time zone database (if not, wait for the library maintainer to include the latest version, or send a PR, ...).

* download the files and recompile:

  1. Configure a custom  directory with the `:data_dir` option.
  2. Download the files manually running the mix task below:
     ```bash
     mix tz.download
     ```
     You may also pass a specific version:
     ```bash
     mix tz.download 2021a
     ```
     In that case delete more recent versions from the folder.
  3. Recompile the dependency:
     ```bash
     mix deps.compile tz --force
     ```
     Or from an iex session to recompile at runtime:
     ```bash
     iex -S mix
     iex(1)> Tz.Compiler.compile()
     ```
     Note that recompilation at runtime is not persistent, run `mix deps.compile tz --force` in addition.

To avoid the updater to run while executing tests, you may conditionally add the child worker in your supervisor. For example:

```elixir
children = [
  MyApp.RepoBase,
  MyApp.Endpoint,
]
|> append_if(Application.get_env(:my_app, :env) != :test, {Tz.UpdatePeriodically, []})
```

```elixir
defp append_if(list, condition, item) do
  if condition, do: list ++ [item], else: list
end
```

In `config.exs`, add `config :my_app, env: Mix.env()`.

Lastly, add the http client `mint` and ssl certificate store `castore` into your `mix.exs` file:

```elixir
defp deps do
  [
    {:castore, "~> 0.1.17"},
    {:mint, "~> 1.4"},
    {:tz, "~> 0.22.0"}
  ]
end
```

### Custom HTTP client

You may implement the `Tz.HTTP.HTTPClient` behaviour in order to use another HTTP client.

Example using [Finch](https://github.com/keathley/finch):
```elixir
defmodule MyApp.Tz.HTTPClient do
  @behaviour Tz.HTTP.HTTPClient

  alias Tz.HTTP.HTTPResponse
  alias MyApp.MyFinch

  @impl Tz.HTTP.HTTPClient
  def request(hostname, path) do
    {:ok, response} =
      Finch.build(:get, "https://" <> Path.join(hostname, path))
      |> Finch.request(MyFinch)

    %HTTPResponse{
      status_code: response.status,
      body: response.body
    }
  end
end
```

A `Tz.HTTP.HTTPResponse` struct must be returned with fields `:status_code` and `:body`.

The custom module must then be passed into the config:
```elixir
config :tz, :http_client, MyApp.Tz.HTTPClient
```

## Usage

To use the `tz` database, either configure it via configuration:
```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

or by calling `Calendar.put_time_zone_database/1`:
```elixir
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
```

or by passing the module name `Tz.TimeZoneDatabase` directly to the functions that need a time zone database:
```elixir
DateTime.now("America/Sao_Paulo", Tz.TimeZoneDatabase)
```

Refer to the [DateTime API](https://hexdocs.pm/elixir/DateTime.html) for more details
about handling datetimes with time zones.

## Performance tweaks

`tz` provides two environment options to tweak performance.

You can decrease **compilation time**, by rejecting time zone periods before a given year:

```elixir
config :tz, reject_time_zone_periods_before_year: 2010
```

By default, no periods are rejected.

For time zones that have ongoing DST changes, period lookups for dates far in the future will result in periods being
dynamically computed based on the IANA data. For example, what is the period for 20 March 2040 for New York (let's
assume that the last rules for New York still mention an ongoing DST change as you read this)? We can't compile periods
indefinitely in the future; by default, such periods are computed until 5 years from compilation time. Dynamic period
computations is a slow operation.

You can decrease **period lookup time** for such periods lookups, by specifying until what year those periods have to be
computed:

```elixir
config :tz, build_time_zone_periods_with_ongoing_dst_changes_until_year: 20 + NaiveDateTime.utc_now().year
```

Note that increasing the year will also slightly increase compilation time, as it will generate more periods to compile.

## Custom storage location of time zone files

By default, the files are stored in the `priv` directory of the `tz` library. You may customize the directory that will hold all of the IANA timezone data. For example, if you want to store the files in your project's `priv` dir instead:

```elixir
config :tz, :data_dir, Path.join(Path.dirname(__DIR__), "priv")
```

## Get the IANA time zone database version

```elixir
Tz.iana_version() == "2022c"
```

## Time zone utility functions

Tz's API is intentionally kept as minimal as possible to implement Calendar.TimeZoneDatabase's behaviour. Utility functions
around time zones are provided by [TzExtra](https://github.com/mathieuprog/tz_extra).

* [`TzExtra.countries_time_zones/1`](https://github.com/mathieuprog/tz_extra#tzextracountries_time_zones1): returns a list of time zone data by country
* [`TzExtra.time_zone_identifiers/1`](https://github.com/mathieuprog/tz_extra#tzextratime_zone_identifiers1): returns a list of time zone identifiers
* [`TzExtra.civil_time_zone_identifiers/1`](https://github.com/mathieuprog/tz_extra#tzextracivil_time_zone_identifiers1): returns a list of time zone identifiers that are tied to a country
* [`TzExtra.countries/0`](https://github.com/mathieuprog/tz_extra#tzextracountries0): returns a list of ISO country codes with their English name
* [`TzExtra.get_canonical_time_zone_identifier/1`](https://github.com/mathieuprog/tz_extra#tzextraget_canonical_time_zone_identifier1): returns the canonical time zone identifier for the given time zone identifier
* [`TzExtra.Changeset.validate_time_zone_identifier/3`](https://github.com/mathieuprog/tz_extra#tzextraChangesetvalidate_time_zone_identifier3): an Ecto Changeset validator, validating that the user input is a valid time zone
* [`TzExtra.Changeset.validate_civil_time_zone_identifier/3`](https://github.com/mathieuprog/tz_extra#tzextraChangesetvalidate_civil_time_zone_identifier3): an Ecto Changeset validator, validating that the user input is a valid civil time zone
* [`TzExtra.Changeset.validate_iso_country_code/3`](https://github.com/mathieuprog/tz_extra#tzextraChangesetvalidate_iso_country_code3): an Ecto Changeset validator, validating that the user input is a valid ISO country code

## Other IANA time zone database implementations

* https://github.com/hrzndhrn/time_zone_info
* https://github.com/lau/tzdata (not recommended due to bugs)

## Installation

Add `tz` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:tz, "~> 0.22.0"}
  ]
end
```

## HexDocs

HexDocs documentation can be found at [https://hexdocs.pm/tz](https://hexdocs.pm/tz).
