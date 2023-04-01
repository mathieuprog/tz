# Tz

Time zone support for Elixir.

The Elixir standard library does not ship with a time zone database. As a result, the functions in the `DateTime`
module can, by default, only operate on datetimes in the UTC time zone. Alternatively (and
[deliberately](https://elixirforum.com/t/14743)), the standard library relies on
third-party libraries, such as `tz`, to bring in time zone support and deal with datetimes in other time zones than UTC.

The `tz` library relies on the [time zone database](https://data.iana.org/time-zones/tzdb/) maintained by
[IANA](https://www.iana.org). As of version 0.26.1, `tz` uses version **tzdata2023c** of the IANA time zone database.

* [Installation and usage](#installation-and-usage)
* [Core principles](#core-principles)
* [Automatic updates](#automatic-time-zone-data-updates)
* [Manual updates](#manual-time-zone-data-updates)
* [Automatic vs manual updates](#automatic-vs-manual-updates)
* [Disable updates in test env](#disable-updates-in-test-environment)
* [Default HTTP client](#default-http-client)
* [Custom HTTP client](#custom-http-client)
* [Performance tweaks](#performance-tweaks)
* [Custom storage location](#custom-storage-location-of-time-zone-data)
* [Get the IANA version](#get-the-iana-time-zone-database-version)
* [Time zone utility functions](#time-zone-utility-functions)
* [Other libraries](#other-time-zone-database-implementations)
* [Acknowledgments](#acknowledgments)

## Installation and usage

Add `tz` for Elixir as a dependency in your `mix.exs` file:

```elixir
def deps do
  [
    {:tz, "~> 0.26.1"}
  ]
end
```

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

## Core principles

### Battle-tested

The `tz` library is tested against nearly 10 million past dates, which includes most of all possible edge cases.

The repo [tzdb_test](https://github.com/mathieuprog/tzdb_test) compares the output of the different available libraries (tz, time_zone_info, tzdata and zoneinfo), and gives some idea of the difference in performance.

### Pre-compiled time zone data

Time zone periods are deducted from the [IANA time zone data](https://data.iana.org/time-zones/tzdb/). A period is a
period of time where a certain offset is observed. For example, in Belgium from 31 March 2019 until 27 October 2019, clock
went forward by 1 hour; as Belgium has a base offset from UTC of 1 hour, this means that during this period, Belgium observed a total offset of 2 hours from UTC time (base UTC offset of 1 hour + DST offset of 1 hour).

The time zone periods are computed and made available in Elixir maps during compilation time, to be consumed by the
[DateTime](https://hexdocs.pm/elixir/DateTime.html#module-time-zone-database) module.

## Automatic time zone data updates

`tz` can watch for IANA time zone database updates and automatically recompile the time zone periods.

To enable automatic updates, add `Tz.UpdatePeriodically` as a child in your supervisor:

```elixir
{Tz.UpdatePeriodically, []}
```

## Manual time zone data updates

You may pass the option `:interval_in_days` in order to configure the frequency of the updates.

```elixir
{Tz.UpdatePeriodically, [interval_in_days: 5]}
```

If you do not wish to update automatically, but still wish to be alerted for new upcoming IANA updates, add
`Tz.WatchPeriodically` as a child in your supervisor:

```elixir
{Tz.WatchPeriodically, []}
```

`Tz.WatchPeriodically` simply logs to your server when a new time zone database is available.

You may pass the options:
* `:interval_in_days`: frequency of the checks
* `:on_update`: a user callback executed when an update is available

For updating IANA data manually, there are 2 options:

* just update the `tz` library in the `mix.exs` file, which hopefully includes the latest IANA time zone database (if not, wait for the library maintainer to include the latest version or send a pull request on GitHub).

* download the files and recompile:

  1. Configure a custom directory with the `:data_dir` option.
  2. Download the files manually by running the mix task below:
     ```bash
     mix tz.download
     ```
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
  4. Check that the version is the one expected:
     ```bash
     iex(2)> Tz.iana_version()
     ```

To force a specific IANA version:

  1. Configure a custom directory with the `:data_dir` option.
  2. Download the files by running the mix task below (say we want the 2021a version):
     ```bash
     mix tz.download 2021a
     ```
  3. Add the `:iana_version` option:
     ```elixir
     config :tz, :iana_version, 2021a
     ```
  4. Recompile the dependency:
     ```bash
     mix deps.compile tz --force
     ```
  5. Check that the version is the one expected:
     ```bash
     iex(2)> Tz.iana_version()
     ```

## Automatic vs manual updates

Some users prefer to use `Tz.WatchPeriodically` (over `Tz.UpdatePeriodically`) to watch and update manually. Example cases:

* Memory-limited systems: small containers or embedded devices may not afford to recompile the time zone data at runtime.
* Restricted environments: the request may be blocked because of security policies.
* Security concerns: some users may prefer to analyze the files coming from external sources (`https://data.iana.org` in this case) before processing.
* Systems interoperability: a user may use some other systems using an older version of the IANA database, and  so the user may want to keep a lower version of the IANA data with `tz` to ensure IANA versions match.

## Disable updates in test environment

To avoid the updater to run while executing tests, you may conditionally add the child worker in your supervisor. For example:

```elixir
children = [
  MyApp.Repo,
  MyApp.Endpoint,
  #...
]
|> append_if(Application.get_env(:my_app, :env) != :test, {Tz.UpdatePeriodically, []})
```

```elixir
defp append_if(list, condition, item) do
  if condition, do: list ++ [item], else: list
end
```

In `config.exs`, add `config :my_app, env: Mix.env()`.

## Default HTTP client

Lastly, add the http client `mint` and ssl certificate store `castore` into your `mix.exs` file:

```elixir
defp deps do
  [
    {:castore, "~> 0.1"},
    {:mint, "~> 1.4"},
    {:tz, "~> 0.26.1"}
  ]
end
```

You may also add custom [options](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-options) for the http client `mint`:

```elixir
config :tz, Tz.HTTP.Mint.HTTPClient,
  proxy: {:http, proxy_host, proxy_port, []}
```

## Custom HTTP client

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

## Performance tweaks

`tz` accepts two environment options to tweak performance.

### Reducing period lookup time

For time zones that have ongoing DST changes, period lookups for dates far in the future result in periods being
dynamically computed based on the IANA data. For example, what is the period for 20 March 2040 for New York (let's
assume that the last rules for New York still mention an ongoing DST change as you read this)? We can't compile periods
indefinitely in the future; by default, such periods are computed until 5 years from compilation time. Dynamic period
computations is a slow operation.

You can decrease **period lookup time** for time zones affected by DST changes, by specifying until what year those periods have to be computed:

```elixir
config :tz, build_dst_periods_until_year: 20 + NaiveDateTime.utc_now().year
```

Note that increasing the year will also slightly increase compilation time, as it generates more periods to compile.

The default setting computes periods for a period of 5 years from the time the code is compiled. Note that if you have added the automatic updater, the periods will be recomputed with every update, which occurs multiple times throughout the year.

### Rejecting old time zone periods

You can slightly decrease **memory usage** and **compilation time**, by rejecting time zone periods before a given year:

```elixir
config :tz, reject_periods_before_year: 2010
```

Note that this option is aimed towards embedded devices as the difference should be insignificant for ordinary servers.

By default, no periods are rejected.

## Custom storage location of time zone data

By default, the files are stored in the `priv` directory of the `tz` library. You may customize the directory that will hold all of the IANA timezone data. For example, if you want to store the files in your project's `priv` dir instead:

```elixir
config :tz, :data_dir, Path.join(Path.dirname(__DIR__), "priv")
```

## Get the IANA time zone database version

```elixir
Tz.iana_version() == "2023a"
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

## Other time zone database implementations

### Based on IANA time zone data

* [time_zone_info](https://github.com/hrzndhrn/time_zone_info)
* [tzdata](https://github.com/lau/tzdata) (not recommended due to bugs)

### Based on OS-supplied zoneinfo files

Recommended for embedded devices.

* [zoneinfo](https://github.com/smartrent/zoneinfo)

## Acknowledgments

The current state of Tz wouldn't have been possible to achieve without the work of the following contributors related to time zones:

* contributors adding time zone support to Elixir ([call for proposal](https://elixirforum.com/t/14743), [initial proposal](https://github.com/elixir-lang/elixir/pull/7914), [final proposal](https://github.com/elixir-lang/elixir/pull/8383));
* contributors to the [time_zone_info](https://github.com/hrzndhrn/time_zone_info) library, based on which Tz could compare its speed and drastically improve performance;
* contributors to the Java `java.time` package, against which Tz is testing its output.
