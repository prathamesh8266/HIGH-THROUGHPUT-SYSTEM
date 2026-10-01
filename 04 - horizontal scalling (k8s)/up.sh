#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cluster_name=yelp-scale
namespace=yelp-scale
context="kind-$cluster_name"
kind_bin="${KIND_BIN:-kind}"

for command_name in docker kubectl "$kind_bin"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command is missing: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ ! -f "$script_dir/.env" ]]; then
    printf 'Create %s/.env from .env.example first.\n' "$script_dir" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
source "$script_dir/.env"
set +a
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}"
# Bash retains CR from a Windows CRLF .env file; PostgreSQL initdb strips it.
POSTGRES_PASSWORD="${POSTGRES_PASSWORD%$'\r'}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}"

docker build -t yelp-fastapi:kind "$script_dir/app"
docker build -t nginx:kind "$script_dir/nginx"

if ! "$kind_bin" get clusters | grep -Fxq "$cluster_name"; then
    "$kind_bin" create cluster --name "$cluster_name" --config "$script_dir/kind.yaml"
fi
"$kind_bin" load docker-image yelp-fastapi:kind --name "$cluster_name"
"$kind_bin" load docker-image nginx:kind --name "$cluster_name"

if ! kubectl --context "$context" get namespace "$namespace" >/dev/null 2>&1; then
    kubectl --context "$context" create namespace "$namespace"
fi

kubectl --context "$context" -n "$namespace" create secret generic postgres-auth \
    --from-literal=password="$POSTGRES_PASSWORD" --dry-run=client -o yaml |
    kubectl --context "$context" -n "$namespace" apply -f -

kubectl --context "$context" -n "$namespace" create configmap yelp-schema \
    --from-file=01-yelp.sql="$script_dir/yelp.sql" --dry-run=client -o yaml |
    kubectl --context "$context" -n "$namespace" apply -f -

kubectl --context "$context" -n "$namespace" apply -f "$script_dir/k8s/postgres.yaml"
kubectl --context "$context" -n "$namespace" rollout status statefulset/postgres --timeout=180s

app_already_exists=false
if kubectl --context "$context" -n "$namespace" get deployment/yelp-api >/dev/null 2>&1; then
    app_already_exists=true
fi
kubectl --context "$context" -n "$namespace" apply -f "$script_dir/k8s/app.yaml"
if [[ "$app_already_exists" == true ]]; then
    kubectl --context "$context" -n "$namespace" rollout restart deployment/yelp-api
fi
kubectl --context "$context" -n "$namespace" rollout status deployment/yelp-api --timeout=180s

nginx_already_exists=false
if kubectl --context "$context" -n "$namespace" get deployment/nginx >/dev/null 2>&1; then
    nginx_already_exists=true
fi
kubectl --context "$context" -n "$namespace" apply -f "$script_dir/k8s/nginx.yaml"
if [[ "$nginx_already_exists" == true ]]; then
    kubectl --context "$context" -n "$namespace" rollout restart deployment/nginx
fi
kubectl --context "$context" -n "$namespace" rollout status deployment/nginx --timeout=180s

kubectl --context "$context" -n "$namespace" apply -f "$script_dir/k8s/public-service.yaml"
if kubectl --context "$context" -n "$namespace" get deployment/yelp-proxy >/dev/null 2>&1; then
    kubectl --context "$context" -n "$namespace" delete deployment/yelp-proxy --wait=false
fi

printf 'Ready at http://localhost:8081/health\n'
