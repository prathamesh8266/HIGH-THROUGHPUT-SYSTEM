CREATE TABLE IF NOT EXISTS public.yelp_businesses (
    id INTEGER PRIMARY KEY,
    time_gmt TEXT,
    phone TEXT,
    organization TEXT,
    olf TEXT,
    rating NUMERIC,
    number_review INTEGER,
    category TEXT,
    country TEXT,
    country_code TEXT,
    state TEXT,
    city TEXT,
    street TEXT,
    building TEXT
);

-- Add automatic IDs to both new and existing tables without changing CSV IDs.
-- Keep allocation ahead of existing records and never move the sequence backward.
DO $yelp_sequence$
DECLARE
    highest_id bigint;
    sequence_value bigint;
    sequence_called boolean;
BEGIN
    LOCK TABLE public.yelp_businesses IN ACCESS EXCLUSIVE MODE;
    CREATE SEQUENCE IF NOT EXISTS public.yelp_businesses_id_seq
        AS integer OWNED BY public.yelp_businesses.id;
    ALTER TABLE public.yelp_businesses
        ALTER COLUMN id SET DEFAULT nextval('public.yelp_businesses_id_seq'::regclass);

    SELECT max(id) INTO highest_id FROM public.yelp_businesses;
    SELECT last_value, is_called INTO sequence_value, sequence_called
        FROM public.yelp_businesses_id_seq;
    PERFORM setval(
        'public.yelp_businesses_id_seq'::regclass,
        greatest(coalesce(highest_id, 1), sequence_value),
        sequence_called OR highest_id IS NOT NULL
    );
END;
$yelp_sequence$;
