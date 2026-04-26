#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_CONFIG_URLS="${APP_CONFIG_URLS:-}"
APP_API_DEFAULT_DOMAIN="${APP_API_DEFAULT_DOMAIN:-}"

cd "${ROOT_DIR}"

flutter pub get

build_args=(
  build
  web
  --no-wasm-dry-run
  --no-web-resources-cdn
  "--dart-define=APP_CONFIG_URLS=${APP_CONFIG_URLS}"
)

if [[ -n "${APP_API_DEFAULT_DOMAIN}" ]]; then
  build_args+=("--dart-define=APP_API_DEFAULT_DOMAIN=${APP_API_DEFAULT_DOMAIN}")
fi

flutter "${build_args[@]}"

build_id="$(date -u +%Y%m%d%H%M%S)"
printf '%s\n' "${build_id}" > "${ROOT_DIR}/build/web/.last_build_id"

bootstrap_file="${ROOT_DIR}/build/web/flutter_bootstrap.js"
if ! grep -q '"mainJsPath":"main.dart.js"' "${bootstrap_file}"; then
  echo "Failed to find main.dart.js bootstrap entry." >&2
  exit 1
fi
perl -0pi -e 's/"mainJsPath":"main\.dart\.js"/"mainJsPath":"main.dart.js?v='"${build_id}"'"/' \
  "${bootstrap_file}"

index_file="${ROOT_DIR}/build/web/index.html"
if ! grep -q 'src="flutter_bootstrap.js"' "${index_file}"; then
  echo "Failed to find flutter_bootstrap.js entry in index.html." >&2
  exit 1
fi
perl -0pi -e 's/src="flutter_bootstrap\.js"/src="flutter_bootstrap.js?v='"${build_id}"'"/' \
  "${index_file}"
perl -0pi -e 's/href="flutter_bootstrap\.js"/href="flutter_bootstrap.js?v='"${build_id}"'"/' \
  "${index_file}"
perl -0pi -e 's/href="main\.dart\.js"/href="main.dart.js?v='"${build_id}"'"/' \
  "${index_file}"

perl -0pi -e 's/_flutter\.loader\.load\(\{/_flutter.loader.load({\n  config: {\n    fontFallbackBaseUrl: "font-fallback\/",\n  },/' \
  "${bootstrap_file}"

font_fallback_root="${ROOT_DIR}/build/web/font-fallback"
font_fallback_files=(
  "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"
  "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.113.woff2"
  "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.115.woff2"
  "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.116.woff2"
  "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.117.woff2"
  "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.118.woff2"
  "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.119.woff2"
)

for font_fallback_file in "${font_fallback_files[@]}"; do
  font_fallback_target="${font_fallback_root}/${font_fallback_file}"
  mkdir -p "$(dirname "${font_fallback_target}")"
  curl -fsSL \
    "https://fonts.gstatic.com/s/${font_fallback_file}" \
    -o "${font_fallback_target}"
done

headers_file="${ROOT_DIR}/web/_headers"
if [[ ! -f "${headers_file}" ]]; then
  echo "Missing Cloudflare Pages headers file: ${headers_file}" >&2
  exit 1
fi
cp "${headers_file}" "${ROOT_DIR}/build/web/_headers"

mkdir -p "${ROOT_DIR}/build/web/payment-icons"
cp "${ROOT_DIR}"/deploy/test-server/static/payment-icons/*.svg \
  "${ROOT_DIR}/build/web/payment-icons/"

rm -f \
  "${ROOT_DIR}/build/web/assets/assets/bin/geoip.dat" \
  "${ROOT_DIR}/build/web/assets/assets/bin/geosite.dat"

echo "Web release build is ready at ${ROOT_DIR}/build/web"
