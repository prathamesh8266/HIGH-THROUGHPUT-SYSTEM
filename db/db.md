# Yelp database inspection notes

The current schema is defined in each stage's `yelp.sql`; use that file to create or update the table. The original manual experiment with an unindexed table is historical. Stage 01 now declares an `id` primary key; stages 02–04 add three secondary indexes.

Connect using the [psql guide](../commands/psql.md), then inspect:

```sql
\d public.yelp_businesses
\di public.*yelp*

SELECT conname AS constraint_name, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.yelp_businesses'::regclass;

SELECT count(*) AS total_rows, min(id), max(id)
FROM public.yelp_businesses;

SELECT count(*) FROM public.yelp_businesses WHERE country = 'USA';
SELECT count(DISTINCT state) FROM public.yelp_businesses;
SELECT count(DISTINCT city) FROM public.yelp_businesses;
SELECT count(DISTINCT organization) FROM public.yelp_businesses;
SELECT count(DISTINCT category) FROM public.yelp_businesses;
```

Earlier inspection of the original million-row CSV recorded these values:

| Query | Recorded count |
| --- | ---: |
| Rows with `country = 'USA'` | 1,000,000 |
| Distinct states | 127 |
| Distinct cities | 12,566 |
| Distinct organizations | 190,703 |
| Distinct categories | 3 |

These are historical observations of the source data, not constraints or assertions about a database after write tests. Synthetic businesses can change the counts. Recheck the live table before comparing benchmarks.

Use the [dataset import guide](README.md) to import CSVs. The importers handle the explicit column order and ID sequence; a bare COPY command does not provide all of those checks.
