#!/usr/bin/env bash
#
# Check that the APIM RPMs install and run on a given RHEL major version.
#
# Runs a UBI "init" container (systemd as PID 1) next to a MongoDB container, installs the Java
# the APIM version needs (21 up to 4.12, 25 from 4.13), nginx and the APIM RPMs the way an
# operator would, then checks services and ports.
#
# Usage:
#   test/local/check-rhel.sh --rhel 9 --version 4.12.21
#   test/local/check-rhel.sh --rhel 10 --rpms apim/4.x
#   test/local/check-rhel.sh --rhel 9 --version 4.13.0~alpha.1 --repo nightly
#
# Single-quoted commands run inside the container, where their variables expand.
# shellcheck disable=SC2016
set -euo pipefail

RHEL=""
VERSION=""
RPMS_DIR=""
REPO="rpms"
KEEP=false
CHECKED=false
MONGO_IMAGE="mongo:7"
TIMEOUT=300

usage() {
  cat <<EOF
Usage: $(basename "$0") --rhel <8|9|10> (--version <x.y.z> | --rpms <dir>) [options]

  --rhel <N>         RHEL major version to test (UBI image registry.access.redhat.com/ubiN/ubi-init)
  --version <V>      APIM version to install from packagecloud (e.g. 4.12.21)
  --rpms <dir>       Install the *.rpm files of a local directory instead (e.g. output of apim/4.x/build.sh)
  --repo <name>      packagecloud repository: rpms (default) or nightly
  --mongo <image>    MongoDB image (default: ${MONGO_IMAGE})
  --timeout <s>      Seconds to wait for APIM to answer (default: ${TIMEOUT})
  --keep             Do not remove the containers on exit (to debug them)
  -h, --help         Show this help

The container runtime is docker, or podman when docker is not installed (override with ENGINE=...).
Tested with Docker Desktop on macOS; the podman path has not been run yet.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rhel) RHEL="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --rpms) RPMS_DIR="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --mongo) MONGO_IMAGE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --keep) KEEP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${RHEL}" =~ ^(8|9|10)$ ]] || { echo "--rhel must be 8, 9 or 10" >&2; usage >&2; exit 2; }
[[ "${REPO}" =~ ^(rpms|nightly)$ ]] || { echo "--repo must be rpms or nightly" >&2; exit 2; }
if [[ -n "${VERSION}" && -n "${RPMS_DIR}" ]] || [[ -z "${VERSION}" && -z "${RPMS_DIR}" ]]; then
  echo "Give exactly one of --version or --rpms" >&2; usage >&2; exit 2
fi
if [[ -n "${RPMS_DIR}" ]]; then
  RPMS_DIR="$(cd "${RPMS_DIR}" && pwd)"
  compgen -G "${RPMS_DIR}/graviteeio-apim-*.rpm" > /dev/null || { echo "No graviteeio-apim-*.rpm in ${RPMS_DIR}" >&2; exit 2; }
fi

# APIM 4.13 requires Java 25, which 4.12 does not support. The version comes from the gateway RPM
# with --rpms (graviteeio-apim-gateway-4x-<version>-<release>.noarch.rpm).
apim_version="${VERSION}"
if [[ -n "${RPMS_DIR}" ]]; then
  gateway_rpm="$(compgen -G "${RPMS_DIR}/graviteeio-apim-gateway-4x-*.rpm" | head -1 || true)"
  [[ -n "${gateway_rpm}" ]] || { echo "No graviteeio-apim-gateway-4x-*.rpm in ${RPMS_DIR}" >&2; exit 2; }
  apim_version="$(basename "${gateway_rpm}" | sed -E 's/^graviteeio-apim-gateway-4x-(.*)-[^-]+\.noarch\.rpm$/\1/')"
fi
[[ "${apim_version}" =~ ^([0-9]+)\.([0-9]+) ]] || { echo "Cannot read the APIM version from '${apim_version}'" >&2; exit 2; }
if (( BASH_REMATCH[1] > 4 || (BASH_REMATCH[1] == 4 && BASH_REMATCH[2] >= 13) )); then JAVA=25; else JAVA=21; fi
if [[ "${RHEL}" == 8 && "${JAVA}" == 25 ]]; then
  echo "APIM ${apim_version} requires Java 25, which RHEL 8 does not ship (java-21-openjdk at most)." >&2
  echo "RESULT: FAIL (APIM ${apim_version} cannot run on RHEL 8 with the OS JDK)"
  exit 1
fi

ENGINE="${ENGINE:-$(command -v docker > /dev/null && echo docker || echo podman)}"
command -v "${ENGINE}" > /dev/null || { echo "Neither docker nor podman found" >&2; exit 2; }

NAME="check-rhel${RHEL}-$$"
NETWORK="${NAME}"
APIM="${NAME}-apim"
MONGO="${NAME}-mongo"
IMAGE="registry.access.redhat.com/ubi${RHEL}/ubi-init"

log() { printf '\n==> %s\n' "$*"; }
in_apim() { "${ENGINE}" exec "${APIM}" bash -c "$1"; }

cleanup() {
  local status=$?
  ${CHECKED} || [[ ${status} -eq 0 ]] || echo "RESULT: FAIL (setup failed before the checks, see above)"
  if ${KEEP}; then
    log "Kept: ${ENGINE} exec -it ${APIM} bash  (remove with: ${ENGINE} rm -f ${APIM} ${MONGO} && ${ENGINE} network rm ${NETWORK})"
  else
    "${ENGINE}" rm -f "${APIM}" "${MONGO}" > /dev/null 2>&1 || true
    "${ENGINE}" network rm "${NETWORK}" > /dev/null 2>&1 || true
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

log "Starting MongoDB and ${IMAGE} with ${ENGINE}"
"${ENGINE}" network create "${NETWORK}" > /dev/null
"${ENGINE}" run -d --name "${MONGO}" --network "${NETWORK}" --network-alias mongodb "${MONGO_IMAGE}" > /dev/null
options=()
[[ -n "${RPMS_DIR}" ]] && options+=(-v "${RPMS_DIR}:/local-rpms:ro")
if [[ "$(basename "${ENGINE}")" == podman ]]; then
  # Podman runs systemd natively.
  options+=(--systemd=always)
else
  # Docker needs a privileged container with the host cgroup tree. On a Linux host, that gives the
  # container root-level access to the host itself.
  options+=(--privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup)
fi
# Pull every time: a cached image would keep answering with the RHEL minor pulled months ago.
"${ENGINE}" run -d --pull=always --name "${APIM}" --network "${NETWORK}" "${options[@]}" "${IMAGE}" > /dev/null

for _ in $(seq 30); do
  state="$(in_apim 'systemctl is-system-running 2>/dev/null' || true)"
  [[ "${state}" =~ ^(running|degraded)$ ]] && break
  sleep 1
done
echo "OS: $(in_apim '. /etc/os-release && echo "${PRETTY_NAME}"'), systemd ${state:-not running}"

log "Installing Java ${JAVA} (APIM ${apim_version}) and nginx"
in_apim "dnf install -y -q java-${JAVA}-openjdk-headless nginx"

if [[ -n "${RPMS_DIR}" ]]; then
  log "Installing local RPMs from ${RPMS_DIR}"
  in_apim 'dnf install -y /local-rpms/graviteeio-apim-*.rpm'
else
  log "Installing APIM ${VERSION} from packagecloud graviteeio/${REPO}"
  in_apim "cat > /etc/yum.repos.d/graviteeio.repo <<'EOF'
[graviteeio]
name=graviteeio
baseurl=https://packagecloud.io/graviteeio/${REPO}/el/7/\$basearch
gpgcheck=1
repo_gpgcheck=1
enabled=1
gpgkey=https://packagecloud.io/graviteeio/${REPO}/gpgkey,https://packagecloud.io/graviteeio/${REPO}/gpgkey/graviteeio-${REPO}-319791EF7A93C060.pub.gpg
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF"
  # The glob also installs parts the meta-package does not require; a check below reports them.
  in_apim "dnf install -y graviteeio-apim-4x-${VERSION} 'graviteeio-apim-*-4x-${VERSION}'"
fi
in_apim "rpm -qa 'graviteeio-apim-*' | sort"

log "Configuring MongoDB, no analytics, and starting services"
# A shell variable does not reach a systemd service: the settings go through a drop-in. There is
# no Elasticsearch: analytics are disabled, or the Gateway reporter and the Management API wait
# for it.
for service in graviteeio-apim-gateway graviteeio-apim-rest-api; do
  in_apim "mkdir -p /etc/systemd/system/${service}.service.d && cat > /etc/systemd/system/${service}.service.d/check-rhel.conf <<'EOF'
[Service]
Environment=gravitee_management_mongodb_uri=mongodb://mongodb:27017/gravitee
Environment=gravitee_ratelimit_mongodb_uri=mongodb://mongodb:27017/gravitee
Environment=gravitee_analytics_type=none
Environment=gravitee_reporters_elasticsearch_enabled=false
EOF"
done
in_apim 'systemctl daemon-reload && systemctl enable --now nginx graviteeio-apim-gateway graviteeio-apim-rest-api'

# Gamma UI ships as its own package: check it when installed, on the port its nginx configuration
# listens on (listen 8086; listen 0.0.0.0:8086; listen [::]:8086 ...).
gamma_pkg="$(in_apim "rpm -qa --qf '%{NAME}\n' 'graviteeio-apim-*gamma*' | head -1")"
gamma_port=""
if [[ -n "${gamma_pkg}" ]]; then
  gamma_port="$(in_apim "rpm -ql ${gamma_pkg} | grep '^/etc/nginx/.*\.conf\$' | xargs -r sed -nE 's/^[[:space:]]*listen[[:space:]]+([^;[:space:]]+).*/\1/p' | grep -oE '[0-9]+\$' | head -1" || true)"
fi

log "Waiting up to ${TIMEOUT}s for the Gateway and the Management API"
start=${SECONDS}
until in_apim 'curl -s -o /dev/null localhost:8082 && curl -s -o /dev/null localhost:8083/management/' 2> /dev/null; do
  if (( SECONDS - start > TIMEOUT )); then echo "Timed out"; break; fi
  sleep 3
done
echo "Ready after $(( SECONDS - start ))s"

results=()
failed=0
check() {
  local label="$1" cmd="$2" output
  if output="$(in_apim "${cmd}" 2>&1)"; then
    results+=("PASS  ${label}")
  else
    results+=("FAIL  ${label}${output:+ ($(echo "${output}" | tail -1))}")
    failed=$((failed + 1))
  fi
}
http_code() { echo "test \"\$(curl -s -o /dev/null -w '%{http_code}' $1)\" = $2"; }

# An operator installs graviteeio-apim-4x, plus the optional Gamma UI: every other part installed
# here must come with the meta-package.
check "graviteeio-apim-4x requires every installed part but Gamma UI" '
  rpm -q graviteeio-apim-4x > /dev/null || { echo "graviteeio-apim-4x is not installed"; exit 1; }
  missing=""
  for part in $(rpm -qa --qf "%{NAME}\n" "graviteeio-apim-*" | grep -vx -e graviteeio-apim-4x -e graviteeio-apim-gamma-ui-4x); do
    rpm -q --whatrequires "${part}" --qf "%{NAME}\n" | grep -qx graviteeio-apim-4x || missing="${missing} ${part}"
  done
  [ -z "${missing}" ] || { echo "not required by graviteeio-apim-4x:${missing}"; exit 1; }'
check "graviteeio-apim-gateway service active" 'systemctl is-active graviteeio-apim-gateway'
check "graviteeio-apim-rest-api service active" 'systemctl is-active graviteeio-apim-rest-api'
check "nginx service active" 'systemctl is-active nginx'
check "Gateway answers on 8082 (404 No context-path matches)" \
  "curl -s localhost:8082 | grep -q 'No context-path matches'"
check "Management API answers on 8083 (portal APIs list, 200)" \
  "$(http_code localhost:8083/portal/environments/DEFAULT/apis 200)"
check "Console served by nginx on 8084" \
  "curl -sf localhost:8084/ | grep -qi '<html' && curl -sI localhost:8084/ | grep -qi '^server: nginx'"
check "Portal served by nginx on 8085" \
  "curl -sf localhost:8085/ | grep -qi '<html' && curl -sI localhost:8085/ | grep -qi '^server: nginx'"
if [[ -n "${gamma_port}" ]]; then
  check "Gamma UI served by nginx on ${gamma_port}" \
    "curl -sfL localhost:${gamma_port}/ | grep -qi '<html' && curl -sI localhost:${gamma_port}/ | grep -qi '^server: nginx'"
elif [[ -n "${gamma_pkg}" ]]; then
  check "Gamma UI served by nginx" "echo 'no nginx listen port found in ${gamma_pkg}'; false"
else
  results+=("SKIP  Gamma UI (no graviteeio-apim-*gamma* package installed)")
fi
if [[ -n "${gamma_pkg}" ]]; then
  # Gamma UI is optional, so the meta-package does not keep it in step: its own conflicts must.
  check "Gamma UI on the Management API version" \
    "test \"\$(rpm -q --qf '%{VERSION}-%{RELEASE}' ${gamma_pkg})\" = \"\$(rpm -q --qf '%{VERSION}-%{RELEASE}' graviteeio-apim-rest-api-4x)\" || { rpm -q ${gamma_pkg} graviteeio-apim-rest-api-4x | tr '\n' ' '; false; }"
fi

if (( failed > 0 )); then
  log "Last logs of the APIM services"
  in_apim 'journalctl -u graviteeio-apim-gateway -u graviteeio-apim-rest-api -u nginx --no-pager -n 40' || true
fi

log "Summary: RHEL ${RHEL} ($(in_apim '. /etc/os-release && echo "${VERSION_ID}"')), APIM ${VERSION:-from ${RPMS_DIR}}"
printf '  %s\n' "${results[@]}"
CHECKED=true
if (( failed > 0 )); then
  echo "RESULT: FAIL (${failed} check(s) failed)"
  exit 1
fi
echo "RESULT: PASS"
