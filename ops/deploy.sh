#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
image=${1:?Usage: bash ops/deploy.sh IMAGE}
docker image inspect "$image" >/dev/null
# A named container locks across the host and Jenkins's separate filesystem.
docker create --name express-demo-deploy-lock --entrypoint node "$image" --version >/dev/null || {
  echo 'Deployment lock exists; inspect it before retrying' >&2; exit 1;
}
trap 'docker rm express-demo-deploy-lock >/dev/null' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
previous=$(docker compose ps -q app)
previous_image=''
if [[ -n "$previous" ]]; then
  previous_image=$(docker inspect --format '{{.Image}}' "$previous")
  docker image tag "$previous_image" express-demo:previous
fi
if APP_IMAGE="$image" docker compose up -d --no-build --wait --wait-timeout 90 app; then
  docker image tag "$image" express-demo:current
  echo "Deployed $image"
else
  docker compose logs --tail=80 app || true
  if [[ -n "$previous_image" ]]; then
    echo 'Deployment failed; restoring the previous image' >&2
    APP_IMAGE=express-demo:previous docker compose up -d --no-build --wait --wait-timeout 90 app
  else
    echo 'First deployment failed; no previous image is available' >&2
  fi
  exit 1
fi
