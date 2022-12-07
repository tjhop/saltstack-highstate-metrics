# saltstack-highstate-metrics

[Saltstack](https://saltproject.io/) is a great configuration management system, but it can be difficult to assess salt's performance, since salt does not natively expose application metrics (in [Prometheus](https://prometheus.io/) format or otherwise).

There is a [salt extension](https://github.com/salt-extensions/saltext-prometheus) that is being worked on, but until that is ready something else is needed. There are some community exporters such as [this one](https://github.com/BonnierNews/saltstack_exporter) and [this more recent one](https://github.com/kpetremann/salt-exporter), which provide varying levels of metrics as well. Both of these exporters run long lived services to expose proper HTTP metrics for prometheus to scrape -- the first works by running a `highstate` on an application-configured schedule, and the latter working by connecting to the salt controller's event bus to observe events.

This project takes a different approach -- it's simply a wrapper script written in Bash to initiate and run a salt highstate on a minion and parse the JSON output to generate metrics. The metrics get written to a textfile for collection by the [Node Exporter's Textfile Collector](https://github.com/prometheus/node_exporter#textfile-collector).

Example of the metrics that get generated:

```shell
root@debian:~# cat /var/lib/prometheus/node-exporter/saltstack-highstate-metrics.prom
# HELP salt_highstate_disabled Static metric indicating if highstates are disabled. 0 is enabled, 1 is disabled.
# TYPE salt_highstate_disabled gauge
salt_highstate_disabled 0

# HELP salt_highstate_run_total Counter of how many times highstates have been run, via /usr/local/bin/saltstack-highstate-metrics.sh.
# TYPE salt_highstate_run_total counter
salt_highstate_run_total 164

# HELP salt_highstate_states Gauge indicating how many states were executed in the last highstate.
# TYPE salt_highstate_states gauge
salt_highstate_states 280

# HELP salt_highstate_states_failed Gauge indicating how many states failed execution in the last highstate.
# TYPE salt_highstate_states_failed gauge
salt_highstate_states_failed 0

# HELP salt_highstate_last_highstate_duration_seconds How long the last highstate took to run, in seconds.
# TYPE salt_highstate_last_highstate_duration_seconds gauge
salt_highstate_last_highstate_duration_seconds 247.57721

# HELP salt_highstate_last_highstate_seconds Unix epoch timestamp of when the last highstate was run via /usr/local/bin/saltstack-highstate-metrics.sh, in seconds.
# TYPE salt_highstate_last_highstate_seconds gauge
salt_highstate_last_highstate_seconds 1670349882
```

The wrapper script can then be run via any mechanism that allows for scheduled jobs -- systemd timers, periodic nomad jobs, etc.
