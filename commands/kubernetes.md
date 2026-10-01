# Kubernetes debugging commands

These commands target the local `yelp-scale` kind cluster explicitly, so they can be run from any directory. The namespace is `yelp-scale` and the context is `kind-yelp-scale`.

## Inspect pods and routing

```bash
kubectl config current-context
kubectl config get-contexts
kubectl --context kind-yelp-scale get nodes -o wide
kubectl --context kind-yelp-scale -n yelp-scale get pods -o wide
kubectl --context kind-yelp-scale -n yelp-scale get deployments,statefulsets,services,pvc
kubectl --context kind-yelp-scale -n yelp-scale get endpointslices -l kubernetes.io/service-name=yelp-api-backends
kubectl --context kind-yelp-scale -n yelp-scale get events --sort-by=.metadata.creationTimestamp
```

Check that the three app pods, two NGINX pods, and `postgres-0` are ready. The public NodePort Service selects NGINX; the headless backend Service publishes ready FastAPI addresses.

For an unhealthy pod, substitute its actual name:

```bash
kubectl --context kind-yelp-scale -n yelp-scale describe pod YOUR_POD_NAME
kubectl --context kind-yelp-scale -n yelp-scale logs YOUR_POD_NAME --tail=100
kubectl --context kind-yelp-scale -n yelp-scale logs YOUR_POD_NAME --previous --tail=100
```

`--previous` reads logs from the preceding container instance when a pod has restarted.

## Open the PostgreSQL shell

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec -it postgres-0 -- sh
```

There must be a **space between `--` and `sh`**. The separator ends kubectl options; `sh` is the command inside the container. The PostgreSQL image uses Alpine, so use `sh` for the shell.

Inside the container:

```bash
psql -U app -d app
```

Or enter psql directly from your host:

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec -it postgres-0 -- psql -U app -d app
```

From the host, execute a single SQL or psql command:

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec postgres-0 -- psql -X -U app -d app -c 'SELECT count(*) FROM public.yelp_businesses;'
kubectl --context kind-yelp-scale -n yelp-scale exec postgres-0 -- psql -X -U app -d app -c '\di public.*yelp*'
```

See [PostgreSQL commands](psql.md) for indexes, query plans, sessions, and generated IDs.

## Inspect workers, proxy configuration, and logs

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec deployment/yelp-api -- printenv WEB_CONCURRENCY
kubectl --context kind-yelp-scale -n yelp-scale exec deployment/nginx -- nginx -T
kubectl --context kind-yelp-scale -n yelp-scale logs -l app=yelp-api --all-containers=true --tail=100 --prefix
kubectl --context kind-yelp-scale -n yelp-scale logs -l app=nginx --all-containers=true --tail=100 --prefix
kubectl --context kind-yelp-scale -n yelp-scale logs postgres-0 --tail=100
```

`exec deployment/...` selects one matching pod. Label-based log commands include every matching pod. The default app setting is one worker per pod, each with a maximum of 10 pooled database connections.

## Check request distribution

```bash
for i in {1..12}; do curl -fsS http://localhost:8081/health; echo; done
```

The response's `pod` field identifies the app replica. To check successive requests over one reused client connection:

```bash
python3 - <<'PYTHON'
import collections
import http.client
import json

connection = http.client.HTTPConnection('localhost', 8081, timeout=5)
counts = collections.Counter()
for _ in range(30):
    connection.request('GET', '/health')
    response = connection.getresponse()
    body = response.read()
    if response.status != 200:
        raise RuntimeError(f'HTTP {response.status}: {body!r}')
    counts[json.loads(body)['pod']] += 1
connection.close()
print(dict(counts))
PYTHON
```

NGINX balances individual requests. Each proxy has its own round-robin position; exact aggregate counts can differ.

## Compare one and three app replicas

These commands change the running deployment. Keep the dataset, worker setting, test timeout, and machine conditions the same. Run from the repository root:

```bash
kubectl --context kind-yelp-scale -n yelp-scale scale deployment/yelp-api --replicas=1
kubectl --context kind-yelp-scale -n yelp-scale rollout status deployment/yelp-api
sleep 6
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db workload-test/k6/test.js

kubectl --context kind-yelp-scale -n yelp-scale scale deployment/yelp-api --replicas=3
kubectl --context kind-yelp-scale -n yelp-scale rollout status deployment/yelp-api
sleep 6
k6 run -e TEST_TYPE=load -e METHOD=GET -e REQUEST_TIMEOUT=100s -e URL=http://localhost:8081/db workload-test/k6/test.js
```

The short wait allows NGINX's backend DNS cache to refresh; confirm ready endpoints before testing. `up.sh` reapplies the manifest's three replicas.

Use `docker stats` to inspect the kind node containers. `kubectl --context kind-yelp-scale -n yelp-scale top pods` provides pod CPU and memory only if Metrics Server is installed; this setup does not install it.

## Apply an updated schema to an existing PostgreSQL volume

Run from the repository root after editing the stage's `yelp.sql`:

```bash
kubectl --context kind-yelp-scale -n yelp-scale exec -i postgres-0 -- psql -X -U app -d app -v ON_ERROR_STOP=1 < "04 - horizontal scalling (k8s)/yelp.sql"
```

Updating the schema ConfigMap alone does not rerun PostgreSQL initialization scripts. This command applies the SQL to the existing database.
