# Horizontal scaling with kind

This stage runs three FastAPI replicas behind two NGINX proxy replicas. The public Kubernetes Service distributes client connections across the proxies. Each proxy uses HTTP round robin to send individual requests to the ready FastAPI pods, including requests from a reused client connection. Each app pod has one Uvicorn worker and its own async PostgreSQL connection pool. A single PostgreSQL StatefulSet keeps the database shared across replicas.

`client -> NodePort Service -> NGINX proxy -> FastAPI pod -> PostgreSQL`

The kind cluster has one control-plane node and two worker nodes. They are all Docker containers on the same machine, so this demonstrates Kubernetes replica scaling and routing, not additional physical capacity.

## Start

Install [Docker](https://docs.docker.com/get-docker/), [kind](https://kind.sigs.k8s.io/docs/user/quick-start/), and [kubectl](https://kubernetes.io/docs/tasks/tools/). Docker must be running. From this directory:

```bash
test -f .env || cp .env.example .env
# Set POSTGRES_PASSWORD in .env
bash up.sh
curl http://localhost:8081/health
```

`up.sh` builds the app and proxy images, creates the `yelp-scale` kind cluster if needed, loads the images onto its nodes, creates the database Secret and schema ConfigMap, and waits for PostgreSQL, all three app replicas, and both proxy replicas to become ready. It can be rerun after editing either image or the Kubernetes manifests. Changes to `kind.yaml` require recreating the cluster.

The API is available at `http://localhost:8081`. In kind, the public Service uses `NodePort 30080`, mapped to host port `8081` by [kind.yaml](kind.yaml). The public Service targets the `nginx` pods. The headless `yelp-api-backends` Service publishes the ready app pod addresses, which [NGINX's configuration](nginx/nginx.conf) resolves and uses as equal-weight round-robin backends.

## Load the Yelp dataset

The table and indexes are initialized from [yelp.sql](yelp.sql) on the first database start. To stream the existing million-row CSV into the database:

```bash
bash import-yelp.sh
# Or pass a different CSV with the same columns:
bash import-yelp.sh /path/to/yelp_database.csv
curl http://localhost:8081/db
```

Supply `db/yelp_database.csv` separately before importing; the large CSV is excluded from Git. See the [dataset guide](../db/README.md) for its 14 required columns. The default file is `../db/yelp_database.csv`. Importing again skips existing IDs. The PostgreSQL volume persists while the kind cluster exists.

PostgreSQL sets the database user's password when it first initializes the volume. If you change `POSTGRES_PASSWORD` later, rotate the password in PostgreSQL too or recreate the cluster before rerunning `up.sh`.

## API and benchmarks

`GET /health` returns status and the responding app pod name. `GET /db` randomly selects one of four Yelp read queries. `POST /dp` inserts a generated Yelp business without requiring a request body. Reads and writes use `public.yelp_businesses`; writes grow the dataset.

From this stage directory, with k6 installed:

```bash
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db ../workload-test/k6/test.js
k6 run -e TEST_TYPE=load -e METHOD=POST -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/dp ../workload-test/k6/test.js
```

Direct commands do not load `.env` and do not export HTML by default. The [shared k6 guide](../workload-test/k6/k6_run.md) covers dashboards, reports, and runner settings. Use the same explicit timeout in every comparison; the example runner uses five seconds while direct script defaults use 100 seconds.

## Verify and compare replicas

```bash
kubectl --context kind-yelp-scale -n yelp-scale get pods -o wide
kubectl --context kind-yelp-scale -n yelp-scale get endpointslices -l kubernetes.io/service-name=yelp-api-backends
for i in {1..12}; do curl -s http://localhost:8081/health; echo; done
```

The `pod` field in `/health` shows which FastAPI replica answered. A client can reuse one TCP connection to a proxy and still reach different app pods on successive HTTP requests. The two proxies keep separate round-robin positions, so exact global request counts are not guaranteed at every instant. Equal request counts also do not imply equal CPU use: `/db` randomly selects queries with different costs.

Compare one and three replicas with the same load test settings. The following commands change the running replica count and restore three afterward. Check ready backend addresses after each scale operation:

```bash
kubectl --context kind-yelp-scale -n yelp-scale scale deployment/yelp-api --replicas=1
kubectl --context kind-yelp-scale -n yelp-scale rollout status deployment/yelp-api
sleep 6  # allow proxy DNS to refresh its ready backend list
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db ../workload-test/k6/test.js
kubectl --context kind-yelp-scale -n yelp-scale scale deployment/yelp-api --replicas=3
kubectl --context kind-yelp-scale -n yelp-scale rollout status deployment/yelp-api
sleep 6
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db ../workload-test/k6/test.js
```

Track throughput, p95 latency, errors, proxy CPU, app CPU, and PostgreSQL CPU. The HTTP proxy adds a network hop and can become a throughput limit. Compare against Compose with equal total worker counts and pool capacity, and measure proxy overhead. Replicas share one database and one physical host, so gains are limited by those resources. With one worker and a pool maximum of ten per app pod, three replicas can open up to 30 app connections; the database is configured for 170 total connections. Increasing both workers and replicas multiplies the possible connections; overlapping pods during rollouts need additional connection capacity.

More pods on this host can use spare CPU cores, but they cannot add physical CPU, memory, or disk capacity. The observed read run was slower than the saved stage 03 report. The current worker settings differ, but the saved report does not record its worker count, and the summary does not identify the bottleneck. See [RESULTS.md](../RESULTS.md) for the measurements and evidence limits.

## Debugging

Open the PostgreSQL container's shell or connect directly to psql:

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec -it postgres-0 -- sh
kubectl --context kind-yelp-scale -n yelp-scale exec -it postgres-0 -- psql -U app -d app
```

There is a space between `--` and the command. Inside psql, inspect the Yelp table and indexes:

```text
\d public.yelp_businesses
\di public.*yelp*
```

See [Kubernetes commands](../commands/kubernetes.md) for logs, pod inspection, request distribution, and schema updates, and [PostgreSQL commands](../commands/psql.md) for EXPLAIN ANALYZE and connection checks. `kubectl top` requires Metrics Server, which `up.sh` does not install; `docker stats` can inspect the kind node containers.

Updating the schema ConfigMap with `up.sh` does not rerun PostgreSQL's initialization scripts on an existing volume. Apply an edited `yelp.sql` explicitly, using the command in the Kubernetes guide.

## Remove the local cluster

To delete the local cluster and its PostgreSQL data:

```bash
kind delete cluster --name yelp-scale
```
