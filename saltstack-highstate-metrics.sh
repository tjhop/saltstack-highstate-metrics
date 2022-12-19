#!/usr/bin/env bash

set -u

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

METRICS_DIR="/var/lib/prometheus/node-exporter"
METRICS_FILE="${METRICS_DIR}/$(basename $0).prom"

METRIC_HIGHSTATE_DISABLED=0
METRIC_HIGHSTATE_RUN_COUNT=0
METRIC_HIGHSTATE_STATE_COUNT=0
METRIC_HIGHSTATE_STATE_FAILED_COUNT=0
METRIC_HIGHSTATE_DURATION=0
METRIC_HIGHSTATE_LAST_RUN=0

write_metrics () {
    echo '[INFO] writing metrics to temp file'
    cat<< METRICS_EOF > "$METRICS_FILE.new"
# HELP salt_highstate_disabled Static metric indicating if highstates are disabled. 0 is enabled, 1 is disabled.
# TYPE salt_highstate_disabled gauge
salt_highstate_disabled $METRIC_HIGHSTATE_DISABLED

# HELP salt_highstate_run_total Counter of how many times highstates have been run, via $0.
# TYPE salt_highstate_run_total counter
salt_highstate_run_total $METRIC_HIGHSTATE_RUN_COUNT

# HELP salt_highstate_states Gauge indicating how many states were executed in the last highstate.
# TYPE salt_highstate_states gauge
salt_highstate_states $METRIC_HIGHSTATE_STATE_COUNT

# HELP salt_highstate_states_failed Gauge indicating how many states failed execution in the last highstate.
# TYPE salt_highstate_states_failed gauge
salt_highstate_states_failed $METRIC_HIGHSTATE_STATE_FAILED_COUNT

# HELP salt_highstate_last_highstate_duration_seconds How long the last highstate took to run, in seconds.
# TYPE salt_highstate_last_highstate_duration_seconds gauge
salt_highstate_last_highstate_duration_seconds $METRIC_HIGHSTATE_DURATION

# HELP salt_highstate_last_highstate_seconds Unix epoch timestamp of when the last highstate was run via $0, in seconds.
# TYPE salt_highstate_last_highstate_seconds gauge
salt_highstate_last_highstate_seconds $METRIC_HIGHSTATE_LAST_RUN
METRICS_EOF

    echo '[INFO] promoting new metrics'
    mv $METRICS_FILE.new $METRICS_FILE
}

# ensure textfile dir exists
[ -d $METRICS_DIR ] || { echo "[INFO] Creating textfile directory"; mkdir -p $METRICS_DIR ; }

# if metrics file already exists, persist relevant metrics/update counters as needed
if [ -f $METRICS_FILE ]; then
        echo '[INFO] Found old metrics file, updating metric values'
        METRIC_HIGHSTATE_RUN_COUNT=$(awk '$1 == "salt_highstate_run_total" { print $2 + 1 }' $METRICS_FILE)
        METRIC_HIGHSTATE_LAST_RUN=$(awk '$1 == "salt_highstate_last_highstate_seconds" { print $2 }' $METRICS_FILE)
fi

# check if highstates are disabled
INDEX=$(salt-call state.list_disabled --out json | jq '.local | index("highstate")')
if [[ $INDEX != "null" ]]; then
                echo '[INFO] highstates are disabled'
                METRIC_HIGHSTATE_DISABLED=1
else
    salt-call state.highstate --out json | tee "$TEMP_DIR/highstate"

    # salt is a PITA.
    # if a highstate is running, the result is a JSON object where the `local`
        # data is a string containing the error that a highstate is running.
    # if there is no highstate running, the result is a JSON object where the
        # `local` return data is a JSON object containing a map of objects
        # correlating to individual state runs.
    #
    # the gnarly jq here takes the return data if it's a string, else it provides
    # a known-bad string "foo" (to satisfy jq's requirement of if-then-else
    # conditional structure), and passes the value into the 'test' filter to see
    # if the string matches the highstate-running error code
    if [[ -f "$TEMP_DIR/highstate" && $(jq '.local | if type=="string" then . else "foo" end | test("function \"state.highstate\" is running as PID")' $TEMP_DIR/highstate) == 'false' ]]; then
        METRIC_HIGHSTATE_STATE_FAILED_COUNT="$(jq '[.local[] | select(.result == false)] | length' $TEMP_DIR/highstate)"
        METRIC_HIGHSTATE_STATE_COUNT="$(jq '[.local[]] | length' $TEMP_DIR/highstate)"
        METRIC_HIGHSTATE_DURATION="$(jq '[.local[].duration] | add / 1000' $TEMP_DIR/highstate)"
    fi

    METRIC_HIGHSTATE_LAST_RUN="$(date +%s)"

    if [[ $METRIC_HIGHSTATE_STATE_FAILED_COUNT > 0 ]]; then
        file="/tmp/$(basename $0)_$METRIC_HIGHSTATE_LAST_RUN.log"
        echo "[ERROR] Failed states detected in last highstate run, saving highstate log file to: $file"
        mv "$TEMP_DIR/highstate" "$file"
    fi
fi

write_metrics
