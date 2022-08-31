# Changelog
## 0.22.x

* Add a mix task to download the IANA time zone data for a given version

## 0.21.x

  * Allow to configure the schedulers:
    * `Tz.UpdatePeriodically` may receive the option `:interval_in_days`
    * `Tz.WatchPeriodically` may receive the options `:interval_in_days` and `on_update`
  * Fixed: schedulers were only running once...
