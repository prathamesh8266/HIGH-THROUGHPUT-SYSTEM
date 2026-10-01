# Linux and WSL debugging commands

Run these in your Linux or WSL terminal. Application containers run through Docker; the commands below inspect the host.

## Check listening ports

```bash
sudo ss -ltnp 'sport = :8080'
sudo ss -ltnp 'sport = :8081'
sudo ss -ltnp 'sport = :5665'
```

8080 is the Compose app port, 8081 is the kind app port, and 5665 is the k6 dashboard port. `ss -ltnp` shows listening TCP sockets with numeric ports and process details. Docker Desktop forwarding may be owned by a Windows process and therefore absent from the WSL listing.

## Check processes and resources

```bash
top
free -h
df -h
ps -eo pid,ppid,%cpu,%mem,args --sort=-%cpu | head -20
pgrep -af k6
```

Observe k6 CPU as well as the service containers: the generator shares this laptop with the system under test. Use `docker stats` for containers and Windows Task Manager for Docker Desktop and whole-machine usage.

## Check the API

```bash
curl -fsS http://localhost:8080/health
curl -fsS http://localhost:8080/db
curl -fsS http://localhost:8081/health
curl -fsS http://localhost:8081/db
curl -sS -o /dev/null -w 'status=%{http_code} connect=%{time_connect}s first_byte=%{time_starttransfer}s total=%{time_total}s\n' http://localhost:8081/db
```

The timing command separates connection setup, time until the first response byte, and total response time for one request. It does not measure database execution time or replace a load test.

See [Docker](docker.md), [Kubernetes](kubernetes.md), and [PostgreSQL](psql.md) commands for service diagnostics.
