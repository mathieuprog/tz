# Changelog

## 0.21.x

  * Allow to configure the schedulers:
    `Tz.UpdatePeriodically` may receive the option `:interval_in_days`
    `Tz.WatchPeriodically` may receive the options `:interval_in_days` and `on_update`
    See README file.
  * Fixed: schedulers were only running once...
