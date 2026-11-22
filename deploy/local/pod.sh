#!/bin/sh
# Manage the local Capsa test pod (Traefik + API) with podman.
#   deploy/local/pod.sh up      build the API image and (re)start the pod
#   deploy/local/pod.sh down    stop and remove the pod
#   deploy/local/pod.sh logs    follow the logs of all containers
#   deploy/local/pod.sh status  show the pod and a health check through Traefik
#   deploy/local/pod.sh capsa ARGS...   run the capsa CLI in the API container,
#                                       e.g. capsa user add papa --admin
#   deploy/local/pod.sh reset   remove the pod and its database volume
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
spec="$here/capsa-pod.yaml"
image=localhost/capsa-api:dev

spec_rendered() {
  sed "s|@REPO@|$repo|g" "$spec"
}

case "${1:-}" in
  up)
    podman build -f "$repo/api/Containerfile" -t "$image" "$repo"
    spec_rendered | podman kube play --replace -
    echo "Waiting for http://capsa.localhost:8080/api/v1/health ..."
    for _ in $(seq 1 30); do
      if curl -fsS http://capsa.localhost:8080/api/v1/health 2>/dev/null; then
        echo
        exit 0
      fi
      sleep 1
    done
    echo "API did not become healthy; see: $0 logs" >&2
    exit 1
    ;;
  down)
    spec_rendered | podman kube down -
    ;;
  reset)
    spec_rendered | podman kube down --force -
    ;;
  capsa)
    shift
    if [ -t 0 ]; then tty=-it; else tty=-i; fi
    exec podman exec $tty capsa-api capsa "$@"
    ;;
  logs)
    podman pod logs -f capsa
    ;;
  status)
    podman pod ps --filter name=capsa
    curl -fsS http://capsa.localhost:8080/api/v1/health && echo
    ;;
  *)
    echo "usage: $0 up|down|logs|status|reset|capsa ARGS..." >&2
    exit 2
    ;;
esac
