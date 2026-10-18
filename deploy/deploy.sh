#!/usr/bin/env bash
# Runs on the SERVER after the image was pushed to GHCR.
set -euo pipefail
cd "$(dirname "$0")/.."          # ~/app, where docker-compose.prod.yml lives

: "${IMAGE:?IMAGE not set}"
: "${OWNER:?OWNER not set}"
: "${GHCR_TOKEN:?GHCR_TOKEN not set}"

echo "==> Deploying $IMAGE"
echo "$GHCR_TOKEN" | docker login ghcr.io -u "${ACTOR:-ci}" --password-stdin
export IMAGE
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d

# Wait until the container reports healthy before cleaning up old images.
for i in $(seq 1 30); do
  cid=$(docker compose -f docker-compose.prod.yml ps -q app)
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)
  [ "$status" = "healthy" ] && break
  [ "$status" = "running" ] && [ "$i" -ge 3 ] && break
  sleep 2
done

if [ "$status" != "healthy" ] && [ "$status" != "running" ]; then
  echo "!! Container not healthy (status=$status), logs:"
  docker compose -f docker-compose.prod.yml logs --tail=50
  exit 1
fi

docker image prune -af --filter "until=168h" >/dev/null
docker logout ghcr.io
echo "==> Deployed OK ($IMAGE)"
