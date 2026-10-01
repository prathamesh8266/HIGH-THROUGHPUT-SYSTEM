import os
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from random import choice
from uuid import uuid4

from fastapi import FastAPI
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool


# Each entry contains a name, a read-only query, and its bound parameters.
YELP_READ_QUERIES = [
    (
        "lookup_by_id",
        "SELECT id, organization, rating, city, state FROM public.yelp_businesses WHERE id = %s LIMIT 20",
        (500000,),
    ),
    (
        "count_organization",
        "SELECT count(*) AS business_count FROM public.yelp_businesses WHERE organization = %s",
        ("Papa John's Pizza",),
    ),
    (
        "city_highly_rated",
        """
        SELECT id, organization, rating, number_review
        FROM public.yelp_businesses
        WHERE city = %s AND rating >= %s
        ORDER BY number_review DESC NULLS LAST
        LIMIT 20
        """,
        ("Alexander City", 4),
    ),
    (
        "most_reviewed_businesses",
        """
        SELECT id, organization, rating, number_review, city
        FROM public.yelp_businesses
        ORDER BY number_review DESC NULLS LAST
        LIMIT 20
        """,
        None,
    ),
]



pool = AsyncConnectionPool(
    kwargs={
        "host": os.environ["DB_HOST"],
        "port": int(os.environ["DB_PORT"]),
        "dbname": os.environ["DB_NAME"],
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
    },
    min_size=1,
    max_size=10,
    open=False,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await pool.open(wait=True)
    try:
        yield
    finally:
        await pool.close()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/db")
async def get_yelp_records():
    query_name, query, parameters = choice(YELP_READ_QUERIES)
    async with pool.connection() as connection:
        async with connection.cursor(row_factory=dict_row) as cursor:
            await cursor.execute(query, parameters)
            rows = await cursor.fetchall()
    return {"query": query_name, "row_count": len(rows), "rows": rows}


@app.post("/dp")
async def create_yelp_record():
    organization = f"Load Test Business {uuid4()}"
    parameters = (
        datetime.now(UTC).isoformat(),
        "+1-202-555-0100",
        organization,
        "https://example.com",
        4.5,
        10,
        "Load Test",
        "USA",
        "US",
        "CA",
        "San Francisco",
        "Load Test Street",
        "1",
    )
    async with pool.connection() as connection:
        async with connection.cursor(row_factory=dict_row) as cursor:
            await cursor.execute(
                """
                INSERT INTO public.yelp_businesses (
                    time_gmt, phone, organization, olf, rating, number_review,
                    category, country, country_code, state, city, street, building
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id, organization, rating, number_review, city, state
                """,
                parameters,
            )
            business = await cursor.fetchone()
    return business
