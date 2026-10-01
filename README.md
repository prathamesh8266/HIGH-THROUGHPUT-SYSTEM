# High Throughput System

A FastAPI and PostgreSQL performance project comparing database indexes, Uvicorn workers, and Kubernetes replicas. k6 measures throughput, latency, and HTTP failures. All current stages run locally; the kind cluster shares the same physical host as the load generator.

## Architecture stages

| Stage | Deployment | Default app workers | Pool maximum per worker | Database connection limit |
| --- | --- | ---: | ---: | ---: |
| [01 — Basic](01%20-%20basic/README.md) | One app and one PostgreSQL container | 1 | 50 | PostgreSQL default: 100 |
| [02 — Database indexing](02%20-%20db%20indexing/README.md) | Same app with three additional Yelp indexes | 1 | 50 | 100 |
| [03 — Multi-worker scaling](03%20-%20multi-worker%20scaling/README.md) | One app container with multiple Uvicorn processes | 10 | 10 | 170 |
| [04 — Horizontal scaling](04%20-%20horizontal%20scalling%20%28k8s%29/README.md) | 3 app pods, 2 NGINX pods, 1 PostgreSQL StatefulSet | 1 per app pod | 10 | 170 |

Compose reads `APP_WORKERS` from each stage's local `.env`; the table shows defaults in the committed manifests. For example, stage 03 with `APP_WORKERS=16` allows up to 160 app database connections. Kubernetes defaults to three app workers and up to 30 connections. Leave database capacity for administration and overlapping pods during rollouts.

All stages expose `GET /health`, `GET /db`, and `POST /dp`. Reads randomly select one of four Yelp queries: ID lookup, organization count, city/rating filtering, or most-reviewed businesses. Writes generate and commit one business row without requiring a request body. Compose stages use port **8080**; Kubernetes uses **8081**.

## Start the basic stage

Install Docker with Compose, Python 3, and k6. For WSL, enable Docker Desktop's Ubuntu integration. Run only one Compose stage on port 8080 at a time.

From the repository root:

```bash
cd "01 - basic"
test -f .env || cp .env.example .env
# Set POSTGRES_PASSWORD in .env before starting.
docker compose up -d --build
bash import-yelp.sh
curl -fsS http://localhost:8080/health
curl -fsS http://localhost:8080/db
curl -fsS -X POST http://localhost:8080/dp
```

Supply the million-row CSV at `db/yelp_database.csv` before importing. It is excluded from Git because it is about 110 MB. The [dataset guide](db/README.md) documents the required columns and import methods. The CSV is supplied separately; this repository does not download it automatically.

For Kubernetes, follow the [stage 04 guide](04%20-%20horizontal%20scalling%20%28k8s%29/README.md), which also requires kind and kubectl.

## Run benchmarks

From the repository root, with a Compose stage running and its dataset loaded:

```bash
bash workload-test/k6/run.sh load read
bash workload-test/k6/run.sh load write
```

Use `stress` or `spike` in place of `load`. See the [k6 guide](workload-test/k6/k6_run.md) for Kubernetes URLs, timeouts, and report handling. Temporary reports beside the runner are ignored; curated reports live in stage directories under `workload-test/k6/`.

[RESULTS.md](RESULTS.md) summarizes the saved reports and the observed Kubernetes run. Record worker counts, pool sizes, dataset size, warm-up, and machine conditions for each comparison. More replicas on the same host can use spare CPU cores, but do not add physical resources. Proxy overhead and a shared database can limit gains.

## Debugging and project notes

- [Linux commands](commands/LINUX_COMMANDS.md): ports, processes, and host resources.
- [Docker commands](commands/docker.md): service status, logs, rebuilding, and database access.
- [Kubernetes commands](commands/kubernetes.md): pods, routing, shells, logs, and replica changes.
- [PostgreSQL commands](commands/psql.md): indexes, query plans, sessions, and sequences.
- [Git review](commands/git.md): ignored files already tracked, staged changes, and push preparation.
- [Work done](workdone.md): implemented stages and verification history.
- [Benchmark plan](ARCHITECTURE-BENCHMARK-PLAN.md): proposed controls and future experiments.

Local credentials, datasets, database volumes, logs, caches, and tool configuration are ignored. Share `.env.example` files with placeholder values. Before pushing, inspect `git status --short` and `git diff --cached`; ignore rules do not remove files already tracked by Git.
