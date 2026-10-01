# Benchmark results

Updated: 2026-10-01. These are local measurements on a shared laptop, not production capacity claims. Values below are extracted from the HTML reports' embedded cumulative metrics; the Kubernetes result is the terminal output supplied during debugging.

## Saved load reports

All six reports recorded up to 1,000 VUs. Rates and latency include the complete run, including ramps. Latency values are **milliseconds**. Cumulative percentiles are used directly; they are not averages of interval percentiles.

| Report | Start time (UTC) | Requests | Requests/s | Average ms | p95 ms | p99 ms | HTTP failures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [01 read](workload-test/k6/01%20-%20basic/load-read.html) | 2026-09-27 16:46:07 | 13,055 | 108.69 | 7,105.50 | 9,500.30 | 9,693.80 | 0.00% |
| [01 write](workload-test/k6/01%20-%20basic/load-write.html) | 2026-09-27 16:50:48 | 79,845 | 665.07 | 1,132.00 | 1,675.90 | 1,782.90 | 0.00% |
| [02 read](workload-test/k6/02%20-%20db%20indexing/load-read.html) | 2026-09-29 17:40:10 | 82,041 | 683.36 | 1,101.70 | 1,492.50 | 1,515.10 | 0.00% |
| [02 write](workload-test/k6/02%20-%20db%20indexing/load-write.html) | 2026-09-29 17:47:18 | 80,995 | 674.67 | 1,115.80 | 1,728.70 | 1,909.10 | 0.00% |
| [03 read](workload-test/k6/03%20-%20multi-worker%20scaling/load-read.html) | 2026-09-30 12:18:23 | 1,121,259 | 9,314.90 | 80.12 | 144.06 | 188.72 | 0.00% |
| [03 write](workload-test/k6/03%20-%20multi-worker%20scaling/load-write.html) | 2026-09-30 12:20:40 | 787,433 | 6,548.00 | 114.27 | 303.06 | 415.25 | 0.00% |

All six reports recorded 100% successful checks and zero HTTP failures. Their thresholds check status and failures; they do not impose a latency target or validate response bodies.

The saved stage 02 read report has about 6.29 times the request rate of stage 01, and the stage 03 read report about 13.63 times stage 02. These are observed differences between runs. Without recorded deployment settings and controlled repeated runs, they cannot establish the gain due solely to indexes or workers.

The current stage 02 code uses synchronous FastAPI handlers and psycopg's `ConnectionPool`. Stage 03 uses async handlers and `AsyncConnectionPool`, with awaited database operations. The transition therefore changes the request concurrency model as well as worker count and pool size. The saved reports do not capture the source revision used for each run, so the observed stage 02–03 improvement cannot be attributed to additional workers alone. Compare sync and async implementations with equal worker counts, pool capacity, and workload settings to measure that change separately.

## Observed Kubernetes read run

The user ran the following from `04 - horizontal scalling (k8s)`:

```bash
k6 run -e TEST_TYPE=load -e METHOD=GET -e URL=http://localhost:8081/db ../workload-test/k6/test.js
```

The script defaults to a 100-second request timeout when none is supplied. This direct command does not load the shared runner's `.env`. No HTML artifact for this run was supplied.

| Metric | Stage 03 saved read report | Kubernetes terminal output |
| --- | ---: | ---: |
| Requests | 1,121,259 | 377,677 |
| Requests/s | 9,314.90 | 3,147.41 |
| Average latency | 80.12 ms | 238.87 ms |
| Median latency | 79.30 ms | 2.43 ms |
| p95 latency | 144.06 ms | 961.30 ms |
| p99 latency | 188.72 ms | 999.27 ms |
| HTTP failures | 0% | 0% |

The Kubernetes run completed about 66% fewer requests per second. The low median and high p95 show that many requests were fast while a subset experienced substantial delays. The summary does not locate those delays.

Read-only inspection during debugging found:

- Three ready FastAPI pods with one Uvicorn worker each, two ready NGINX pods, and a shared PostgreSQL pod.
- 1,000,001 Yelp rows, with the primary key and all three expected secondary indexes present.
- All four application reads using indexes in EXPLAIN ANALYZE, with roughly 0.05–0.28 ms execution times without load. Those timings do not establish SQL performance during the load test.
- Stage 03's local Compose settings resolved to 16 workers, while its committed manifest defaults to 10. The saved HTML report does not identify the worker setting actually used for that run.

Three single-worker pods allow up to 30 pooled app database connections. A 16-worker Compose setting allows up to 160. The Kubernetes route adds NodePort and NGINX, and all kind nodes share the same physical host. Worker count, network overhead, proxy capacity, app queues, database contention, and generator load are possible contributors; the current evidence does not isolate their costs.

Compare one versus three pods within Kubernetes, then compare Compose and Kubernetes with equal total workers and pool capacity. Capture CPU, memory, connection activity, and request timing during each run. See the [Kubernetes commands](commands/kubernetes.md).

## Evidence needed for comparisons

The current shared script selects four Yelp reads at random, or executes a separate write test. Its profiles use a closed workload model: every VU waits for its current request, so slower responses reduce new request arrivals. Equal VUs therefore do not mean equal incoming request rates. See [k6's workload model documentation](https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/open-vs-closed/).

Record the exact command, timeout, source revision, worker count, replicas, pool maximum, PostgreSQL settings, indexes, dataset size, warm-up, and host resources with each report. Write tests grow the table. Capture steady-stage metrics and resource observations, repeat comparisons, and choose error and latency targets before claiming sustainable capacity.

Reports do not provide per-query timings, synchronized CPU or pool-wait measurements, or a complete error breakdown. Current settings cannot be assumed to describe an older run. Temporary reports directly under `workload-test/k6/` are ignored; reviewed stage reports remain shareable.
