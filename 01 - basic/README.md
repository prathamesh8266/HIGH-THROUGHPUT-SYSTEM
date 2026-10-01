# Basic baseline

One FastAPI container and one PostgreSQL 17 container, exposed at `http://localhost:8080`.

This stage provides the baseline before adding secondary indexes. The application uses async request handlers and an async PostgreSQL connection pool.

## Start

Install Docker with Compose and k6. In WSL, enable Docker Desktop's Ubuntu integration. From this directory:

```bash
test -f .env || cp .env.example .env
# Set POSTGRES_PASSWORD in .env; optionally set APP_WORKERS.
docker compose up -d --build
curl -fsS http://localhost:8080/health
```

Run only one Compose stage on port 8080 at a time. `docker compose down` stops this stage and preserves its named database volume. PostgreSQL sets its password when the volume is first initialized; changing `.env` later also requires rotating the database password.

## Load the Yelp dataset

Supply `../db/yelp_database.csv` separately; the large CSV is excluded from Git. It contains 14 columns and the project dataset has 1,000,000 records. With PostgreSQL running:

```bash
bash import-yelp.sh
# Or choose another compatible CSV:
bash import-yelp.sh /path/to/yelp_database.csv
curl -fsS http://localhost:8080/db
```

The shell importer applies the schema, skips existing IDs, synchronizes the ID sequence, and runs ANALYZE. Invalid input rolls back the import. See the [dataset guide](../db/README.md) for the exact header and alternative paths.

Only the `id` primary-key index is declared in [yelp.sql](yelp.sql). Initialization SQL runs automatically only on a fresh database volume. Apply the schema and sequence configuration to an existing database with:

```bash
docker compose exec -T db psql -X -U app -d app -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/02-yelp.sql
```

This preserves rows and synchronizes generated IDs. The migration locks the table while configuring the sequence; creating additional indexes may also take time on a populated table.

## API

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/health` | Returns app status; it does not execute a database query. |
| GET | `/db` | Randomly selects one of four read queries against `public.yelp_businesses`. |
| POST | `/dp` | Inserts and commits one generated Yelp business; no request body required. |

The four reads are ID lookup, exact organization count, city/rating filtering, and the 20 most-reviewed businesses. Responses include `query`, `row_count`, and `rows`. Writes return the saved ID and business fields. Each write grows the same dataset used by the read tests.

```bash
curl -fsS http://localhost:8080/db
curl -fsS -X POST http://localhost:8080/dp
```

`init.sql` still creates the legacy `test` table on fresh volumes; current endpoints use `yelp_businesses`.

## Workers and database connections

Compose passes `APP_WORKERS` to Uvicorn through `WEB_CONCURRENCY`, defaulting to **1** when unset or empty. Each worker creates its own pool with `min_size=1` and `max_size=50`. The default app connection ceiling is **50**; PostgreSQL's configured connection limit is **100**. Leave spare connections when changing worker counts.

After editing `.env`, recreate the app:

```bash
docker compose up -d --build --force-recreate --no-deps app
docker compose exec -T app printenv WEB_CONCURRENCY
```

## Load tests and debugging

With k6 installed and the dataset loaded, run from this directory:

```bash
bash ../workload-test/k6/run.sh load read
bash ../workload-test/k6/run.sh load write
```

Use `stress` or `spike` for other profiles. The shared runner saves temporary HTML reports in `../workload-test/k6/`; copy selected results into a named stage directory to preserve them. The [k6 guide](../workload-test/k6/k6_run.md) covers URLs, timeout differences between direct commands and the runner, and report saving.

Monitor services during a run:

```bash
docker compose ps
docker compose logs --tail=100 app db
docker stats
docker compose exec db psql -U app -d app
```

Inside psql, use `\d public.yelp_businesses` and `\di public.*yelp*` to inspect the table and indexes. See [Docker commands](../commands/docker.md), [PostgreSQL commands](../commands/psql.md), and [results](../RESULTS.md).

Keep worker counts, pool sizes, dataset size, load profile, timeouts, and machine conditions recorded for each comparison. A passing HTTP-status threshold does not establish a latency target or validate response contents.
