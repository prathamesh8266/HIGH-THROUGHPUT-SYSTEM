# Yelp dataset and CSV import

Place the project's Yelp CSV at `db/yelp_database.csv`. The local file contains 1,000,000 records and is about 110 MB, so it is excluded from Git. Obtain the same dataset separately; there is no automatic download or bundled CSV in a fresh clone.

The required header and column order are:

```text
ID,Time_GMT,Phone,Organization,OLF,Rating,NumberReview,Category,Country,CountryCode,State,City,Street,Building
```

The table retains all 14 fields with snake_case column names. IDs and review counts are integers, ratings are numeric, and time, phone, address, and other descriptive fields are text. Unquoted empty CSV fields become SQL NULL. [Database notes](db.md) contain inspection queries.

## Stage 01: schema setup and repeatable import

From `01 - basic`, with its PostgreSQL container running:

```bash
bash import-yelp.sh
# Or supply a compatible CSV:
bash import-yelp.sh /path/to/yelp_database.csv
```

The shell importer applies the stage 01 schema, copies through a temporary table, skips existing IDs, advances the generated-ID sequence, and runs ANALYZE. The import is transactional and preserves existing rows. It defaults to `../db/yelp_database.csv`.

## Stages 02 and 03: import into an empty Docker database

Each Compose stage has a separate persistent volume. From the chosen stage directory, such as `02 - db indexing`:

```bash
python3 ../db/import_yelp.py --container "$(docker compose ps -q db)"
docker compose exec -T db psql -X -U app -d app -c 'ANALYZE public.yelp_businesses;'
```

The table must already exist and be empty. Fresh volumes initialize it from the stage's `yelp.sql`. For an existing volume without the schema, apply it first:

```bash
docker compose exec -T db psql -X -U app -d app -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/02-yelp.sql
```

The [Python importer](import_yelp.py) uses Python's standard library and the Docker CLI. It validates the header and record widths, streams COPY without holding the dataset in memory, and checks the imported count before committing. It refuses a populated table, takes a table lock to prevent competing writers, and synchronizes an existing ID sequence. It does not create tables or indexes and does not run ANALYZE.

Alternatively, from the repository root, find the PostgreSQL container and provide its name or ID:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}'
python3 db/import_yelp.py --container YOUR_POSTGRES_CONTAINER \
  --csv /path/to/yelp_database.csv --database app --user app
```

`--podname` remains an alias for `--container`; both name a Docker container, not a Kubernetes pod. No CSV copy into the container is needed.

## Stage 04: Kubernetes import

From `04 - horizontal scalling (k8s)`, after `bash up.sh`:

```bash
bash import-yelp.sh
# Or supply another compatible CSV:
bash import-yelp.sh /path/to/yelp_database.csv
```

This streams the CSV through `kubectl exec -i` into `postgres-0`, skips existing IDs, synchronizes the sequence, and runs ANALYZE. The volume persists while the kind cluster exists; deleting the cluster deletes this local database.

## Verify

For Compose, from the running stage directory:

```bash
docker compose exec -T db psql -X -U app -d app -c 'SELECT count(*) AS rows, min(id), max(id) FROM public.yelp_businesses;'
```

For Kubernetes, from any directory:

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec postgres-0 -- psql -X -U app -d app -c 'SELECT count(*) AS rows, min(id), max(id) FROM public.yelp_businesses;'
```

The source dataset spans IDs 1–1,000,000. Write benchmarks add generated businesses, so later row counts and maximum IDs may be larger. Avoid imports during benchmark comparisons and record the starting dataset size.
