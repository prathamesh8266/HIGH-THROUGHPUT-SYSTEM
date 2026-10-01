# k6 read and write benchmarks

Install the k6 CLI. All stages use the shared [test.js](test.js) and [run.sh](run.sh) in this directory. Run from the repository root with one stage started and its Yelp dataset loaded.

## Run with the shared runner

```bash
bash workload-test/k6/run.sh load read
bash workload-test/k6/run.sh load write
```

Reads send `GET /db`; writes send `POST /dp`. Every successful write commits a generated business into the same Yelp table, so write tests change the dataset size. Apply the stage's `yelp.sql` to an existing database before testing generated IDs.

| Profile | Read command from this directory | Write command from this directory | Reports |
| --- | --- | --- | --- |
| Load | `bash run.sh load read` | `bash run.sh load write` | `load-read.html`, `load-write.html` |
| Stress | `bash run.sh stress read` | `bash run.sh stress write` | `stress-read.html`, `stress-write.html` |
| Spike | `bash run.sh spike read` | `bash run.sh spike write` | `spike-read.html`, `spike-write.html` |

The runner changes into its own directory, sources its local `.env` when present, enables the dashboard, and saves the selected report there. A rerun overwrites the same profile/operation report. Open `http://localhost:5665` while the test runs.

The script defines the stages:

- Load: 30-second ramp to 1,000 VUs, 60-second hold, 30-second ramp down.
- Stress: successive 30-second ramps and holds at 1,000, 2,500, and 5,000 VUs, then a 30-second ramp down.
- Spike: 10-second ramp to 100, 20-second hold, one-second jump to 5,000, 10-second hold, one-second return to 100, 30-second recovery, 10-second ramp down.

These settings are experiments, not demonstrated capacity limits. Each VU waits for its request before starting the next iteration. Equal VUs do not guarantee equal request rates.

## Request configuration and timeouts

From this directory:

```bash
test -f .env || cp .env.example .env
```

The example sets:

```bash
BASE_URL=http://localhost:8080
METHOD=GET
REQUEST_TIMEOUT=5s
READ_URL=
WRITE_URL=
```

`READ_URL` and `WRITE_URL` override their full endpoints. For reads, the runner also accepts the older `URL` setting. Without an operation argument, `METHOD` selects reads or writes. Set `BASE_URL=http://localhost:8081` in the runner's `.env` for Kubernetes. Leave stale `READ_URL`, `WRITE_URL`, and `URL` settings empty if using the base URL.

A direct `k6 run` does **not** source `.env`. The script defaults to a **100-second timeout** when no `REQUEST_TIMEOUT` is supplied; the example runner configuration uses **5 seconds**. Use an explicit equal timeout for comparisons.

Extra flags follow the operation, for example:

```bash
bash run.sh load read --stage 5s:1 -e REQUEST_TIMEOUT=100s
```

The runner appends its selected `TEST_TYPE`, `METHOD`, and `URL` after extra flags. Configure endpoint overrides through its `.env`; flags for those three values are overridden by the runner.

## Direct commands

From the repository root:

```bash
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8080/db workload-test/k6/test.js
k6 run -e TEST_TYPE=load -e METHOD=POST -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8080/dp workload-test/k6/test.js

# Kubernetes read benchmark:
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db workload-test/k6/test.js
```

To save a Kubernetes HTML report directly:

```bash
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_PERIOD=1s K6_WEB_DASHBOARD_EXPORT=workload-test/k6/load-read.html k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db workload-test/k6/test.js
```

Change `TEST_TYPE` and the report filename for stress or spike. See the [k6 dashboard documentation](https://grafana.com/docs/k6/latest/results-output/web-dashboard/).

## Preserve selected results

Temporary HTML, CSV, and JSON output directly under `workload-test/k6/` is ignored. Curated reports inside named stage directories are kept in Git, including the older `01 - basic/archive/` reports.

After reviewing a run, copy its report from the repository root:

```bash
mkdir -p "workload-test/k6/04 - horizontal scalling (k8s)"
cp workload-test/k6/load-read.html "workload-test/k6/04 - horizontal scalling (k8s)/load-read.html"
```

This example replaces any report at that destination. Use a distinct filename for repeated or differently configured runs. Save the exact command, timestamp, source revision, worker count, replicas, pool sizes, database connections, row count, timeouts, and resource observations alongside it. HTML reports do not capture all of that deployment context.

## Interpret and debug

Thresholds require zero HTTP failures, every status-200 check passing, and at least one request. There is **no latency threshold** and payloads are not validated. A successful test can therefore still have slow responses.

`REQUEST_TIMEOUT` limits the HTTP client's wait, not PostgreSQL execution. Overall latency includes ramp and recovery stages. Compare the steady stage as well as the cumulative summary and watch the generator's CPU.

Use [Docker commands](../../commands/docker.md), [Kubernetes commands](../../commands/kubernetes.md), and [psql commands](../../commands/psql.md) while the test runs. See [RESULTS.md](../../RESULTS.md) for saved measurements.
