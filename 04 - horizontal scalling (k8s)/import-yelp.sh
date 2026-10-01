#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
csv_file="${1:-$script_dir/../db/yelp_database.csv}"

if [[ ! -r "$csv_file" ]]; then
    printf 'Cannot read CSV: %s\n' "$csv_file" >&2
    exit 1
fi

expected_header='ID,Time_GMT,Phone,Organization,OLF,Rating,NumberReview,Category,Country,CountryCode,State,City,Street,Building'
IFS= read -r actual_header < "$csv_file"
actual_header="${actual_header%$'\r'}"
actual_header="${actual_header#$'\xEF\xBB\xBF'}"
if [[ "$actual_header" != "$expected_header" ]]; then
    printf 'CSV column names or order do not match yelp_database.csv.\n' >&2
    exit 1
fi

columns='id, time_gmt, phone, organization, olf, rating, number_review, category, country, country_code, state, city, street, building'

printf 'Importing %s into public.yelp_businesses...\n' "$csv_file"
kubectl --context kind-yelp-scale -n yelp-scale exec -i pod/postgres-0 -- \
    psql -X -U app -d app -v ON_ERROR_STOP=1 --single-transaction \
    -c 'CREATE TEMP TABLE yelp_import (LIKE public.yelp_businesses) ON COMMIT DROP;' \
    -c "COPY yelp_import ($columns) FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');" \
    -c "INSERT INTO public.yelp_businesses ($columns) SELECT $columns FROM yelp_import ON CONFLICT (id) DO NOTHING;" \
    -c "$(cat "$script_dir/yelp.sql")" \
    -c 'ANALYZE public.yelp_businesses;' \
    -c "SELECT count(*) AS total_rows, min(id) AS first_id, max(id) AS last_id FROM public.yelp_businesses;" \
    < "$csv_file"
