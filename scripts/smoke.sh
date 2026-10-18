#!/usr/bin/env bash
set -euo pipefail
base=${1:-http://127.0.0.1:8000}
curl --fail --silent --show-error "$base/health/ready"
curl --fail --silent --show-error "$base/predict" -H 'Content-Type: application/json'   -d '{"text":"This deployment works beautifully"}' | python3 -c  'import json,sys; x=json.load(sys.stdin); assert x["label"] == "POSITIVE"; assert 0 <= x["score"] <= 1; print(x)'
