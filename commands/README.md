# Debugging commands

Commands collected while starting services, importing the dataset, inspecting indexes, and investigating the Kubernetes throughput result.

| Guide | Use |
| --- | --- |
| [Linux and WSL](LINUX_COMMANDS.md) | Listening ports, processes, resources, and curl timings |
| [Docker and Compose](docker.md) | Service status, logs, rebuilds, worker counts, and persistent databases |
| [Kubernetes](kubernetes.md) | Pods, endpoint routing, working exec syntax, logs, and replica comparisons |
| [PostgreSQL](psql.md) | Table/index definitions, SQL plans, sessions, row counts, and generated IDs |
| [Git review](git.md) | Ignore rules, already tracked local files, staged changes, and push preparation |

Each guide states whether commands run on the host, from a Compose stage directory, inside a container, or inside psql. Kubernetes examples use the explicit `kind-yelp-scale` context and `yelp-scale` namespace.

Load-test commands and report handling are documented in the [shared k6 guide](../workload-test/k6/k6_run.md).
