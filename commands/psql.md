# PostgreSQL debugging commands

## Connect

From a Compose stage directory:

```bash
docker compose exec db psql -U app -d app
```

For the kind cluster, from any directory:

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec -it postgres-0 -- psql -U app -d app
```

The following commands run **inside psql**, rather than the host shell. Backslash commands do not require a semicolon; SQL statements do.

## Inspect databases, tables, and indexes

| Command | What it shows |
| --- | --- |
| `\l` | Databases |
| `\c app` | Connect to the app database |
| `\conninfo` | Current connection |
| `\dn` | Schemas |
| `\dt public.*` | Public tables |
| `\d public.yelp_businesses` | Yelp columns, defaults, constraints, and indexes |
| `\di` | Indexes visible in the current search path |
| `\di public.*yelp*` | Yelp indexes in the public schema |
| `\du` | Database roles |
| `\timing on` | Display elapsed time for subsequent SQL commands |
| `\x auto` | Expand wide query results when useful |
| `\q` | Exit psql |

Index definitions as SQL results:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'yelp_businesses'
ORDER BY indexname;
```

Stage 01 declares only `yelp_businesses_pkey`. Stages 02–04 additionally declare `idx_yelp_organization`, `idx_yelp_city_rating`, and `idx_yelp_most_reviewed`. Inspect the live database: SQL files edited after volume initialization do not apply automatically.

## Verify the dataset and generated IDs

```sql
SELECT count(*) AS rows, min(id) AS first_id, max(id) AS last_id,
       pg_size_pretty(pg_total_relation_size('public.yelp_businesses')) AS total_size
FROM public.yelp_businesses;

SELECT pg_get_serial_sequence('public.yelp_businesses', 'id') AS id_sequence;

SELECT column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'yelp_businesses' AND column_name = 'id';

SELECT last_value, is_called FROM public.yelp_businesses_id_seq;
```

The original CSV has IDs 1–1,000,000. `POST /dp` adds rows with generated IDs, so later row counts can exceed one million. Sequence gaps are normal; do not reset the sequence downward to fill them.

## Explain the four application reads

`EXPLAIN (ANALYZE, BUFFERS)` executes the statement and reports its plan, timing, and buffer activity. These examples are reads. Timing without load does not establish database performance during a benchmark.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, organization, rating, city, state
FROM public.yelp_businesses WHERE id = 500000 LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS business_count
FROM public.yelp_businesses WHERE organization = 'Papa John''s Pizza';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, organization, rating, number_review
FROM public.yelp_businesses
WHERE city = 'Alexander City' AND rating >= 4
ORDER BY number_review DESC NULLS LAST LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, organization, rating, number_review, city
FROM public.yelp_businesses
ORDER BY number_review DESC NULLS LAST LIMIT 20;
```

Look for the expected index names, actual execution time, rows scanned, and disk reads. An index can be present without being selected by the planner.

## Inspect database connections during a test

```sql
SHOW max_connections;

SELECT state, wait_event_type, wait_event, count(*) AS connections
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state, wait_event_type, wait_event
ORDER BY connections DESC;

SELECT pid, state, wait_event_type, wait_event,
       now() - query_start AS elapsed, left(query, 200) AS query
FROM pg_stat_activity
WHERE datname = current_database() AND state = 'active' AND pid <> pg_backend_pid()
ORDER BY query_start;
```

Repeat the preceding query every two seconds:

```text
\watch 2
```

Ctrl+C stops watching. Idle connections are often retained pool connections. A snapshot cannot reveal all application queues or prove the database is the bottleneck.

After a CSV import, update planner statistics:

```sql
ANALYZE public.yelp_businesses;
```

The stage 01 and Kubernetes shell importers already do this. The Python Docker importer requires the explicit ANALYZE step.
