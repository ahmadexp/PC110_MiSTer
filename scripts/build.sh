#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker_bin="${DOCKER_BIN:-docker}"
docker_context="${DOCKER_CONTEXT:-colima-pc110-quartus}"
quartus_image="${QUARTUS_IMAGE:-ghcr.io/raetro/quartus:mister}"

"${docker_bin}" --context "${docker_context}" run --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  -v "${repo_dir}:/build" \
  -w /build \
  "${quartus_image}" \
  quartus_sh --flow compile PC110.qpf

test -s "${repo_dir}/output_files/PC110.rbf"
mkdir -p "${repo_dir}/artifacts"
cp "${repo_dir}/output_files/PC110.rbf" "${repo_dir}/artifacts/PC110.rbf"
echo "Built ${repo_dir}/artifacts/PC110.rbf"
