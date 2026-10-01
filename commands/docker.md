# Docker and Compose debugging commands

Run Compose commands from the stage directory, such as `03 - multi-worker scaling`. The three Compose stages each expose port 8080; stop the previous stage before starting another.

## Start, inspect, and stop

```bash
docker compose up -d --build
docker compose ps
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker compose logs --tail=100 app db
docker compose logs -f --tail=100 app
docker stats
```

Stop log streaming with Ctrl+C. `docker stats` shows current CPU, memory, and I/O; capture it during the benchmark to investigate saturation.

```bash
docker compose down
```

This stops the stage and preserves the named PostgreSQL volume. Adding `--volumes` deletes the persisted data; use that only when deliberately resetting the dataset.

## Rebuild the app and verify workers

After changing app code or `APP_WORKERS` in `.env`:

```bash
docker compose up -d --build --force-recreate --no-deps app
docker compose exec -T app printenv WEB_CONCURRENCY
docker compose top app
```

Every Uvicorn worker creates a separate database pool. Count total workers and pool connections when comparing Compose with Kubernetes replicas. Avoid publishing expanded `docker compose config` output: it includes local database credentials. `docker compose config --quiet` validates the configuration without printing them.

## Open a shell or PostgreSQL

```bash
docker compose exec app sh
docker compose exec db sh
docker compose exec db psql -U app -d app
```

For a SQL query from the host:

```bash
docker compose exec -T db psql -X -U app -d app -c 'SELECT count(*) AS rows FROM public.yelp_businesses;'
docker compose exec -T db psql -X -U app -d app -c '\di public.*yelp*'
```

`-T` disables terminal allocation for scripts. `psql -X` avoids loading local psql startup settings.

## Apply schema changes to an existing volume

```bash
docker compose exec -T db psql -X -U app -d app -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/02-yelp.sql
```

PostgreSQL initialization scripts run only when the volume is first created. This command explicitly applies the stage's Yelp schema, generated-ID sequence, and declared indexes to existing data.

See the [dataset guide](../db/README.md) for CSV import and [psql commands](psql.md) for query plans and connection diagnostics.
