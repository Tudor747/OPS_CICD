#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/docker" <<'MOCK'
#!/usr/bin/env bash
echo "${APP_IMAGE:-unset}|$*" >> "$TRACE"
case "$*" in
  'create '*) [[ "$SCENARIO" != locked ]];;
  'compose ps -q app') [[ "$SCENARIO" == first ]] || echo old-container;;
  'inspect '*) echo sha256:old;;
  'compose up '*) [[ "$SCENARIO" == success || "${APP_IMAGE:-}" == express-demo:previous ]];;
  *) exit 0;;
esac
MOCK
chmod +x "$scratch/docker"
export PATH="$scratch:$PATH"
export TRACE="$scratch/trace"
for SCENARIO in success failure first locked; do
  export SCENARIO
  : > "$TRACE"
  status=0
  bash ops/deploy.sh express-demo:new > "$scratch/output" 2>&1 || status=$?
  if [[ "$SCENARIO" == success ]]; then
    [[ $status -eq 0 ]]
    grep -q 'image tag express-demo:new express-demo:current' "$TRACE"
  else
    [[ $status -ne 0 ]]
    ! grep -q 'image tag express-demo:new express-demo:current' "$TRACE"
  fi
  case "$SCENARIO" in
    failure) grep -q 'express-demo:previous|compose up' "$TRACE";;
    first) ! grep -q 'express-demo:previous|compose up' "$TRACE";;
    locked) ! grep -q 'compose up' "$TRACE"; ! grep -q 'rm express-demo-deploy-lock' "$TRACE";;
  esac
  if [[ "$SCENARIO" != locked ]]; then grep -q 'rm express-demo-deploy-lock' "$TRACE"; fi
  echo "PASS: $SCENARIO"
done
