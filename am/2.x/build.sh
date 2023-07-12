#!/bin/bash

# Import common scripts
. ../../common.sh

PKGNAME="graviteeio-am"
DESC="Gravitee.io Access Management 2.x"

prepare_am_build() {
  local componentName
  local isUI
  local isBack

  local OPTIND o
  while getopts 'n:ub' o; do
    case "${o}" in
      n)
        componentName="${OPTARG}"
        ;;
      u)
        isUI=true
        ;;
      b)
        isBack=true
        ;;
      ?)
        echo "script usage: prepare_am_build [-n componentName] [-u] [-b]" >&2
        exit 1
        ;;
    esac
  done
  shift $((OPTIND -1))

  rm -fr build/skel/

  mkdir -p "${TEMPLATE_DIR}/opt/graviteeio/am"
  cp -fr ".staging/graviteeio-am-full-${VERSION_WITH_QUALIFIER}/graviteeio-am-${componentName}-${VERSION_WITH_QUALIFIER}" "${TEMPLATE_DIR}/opt/graviteeio/am"
  ln -sf "${TEMPLATE_DIR}/opt/graviteeio/am/graviteeio-am-${componentName}-${VERSION_WITH_QUALIFIER}" "${TEMPLATE_DIR}/opt/graviteeio/am/${componentName}"

  if [ -n "${isBack}" ]; then
    mkdir -p "${TEMPLATE_DIR}/etc/systemd/system/"
    cp "build/files/systemd/graviteeio-am-${componentName}.service" "${TEMPLATE_DIR}/etc/systemd/system/"

    mkdir -p "${TEMPLATE_DIR}/etc/init.d"
    cp "build/files/init.d/graviteeio-am-${componentName}" "${TEMPLATE_DIR}/etc/init.d"
  fi

  if [ -n "${isUI}" ]; then
    mkdir -p "${TEMPLATE_DIR}/etc/nginx/conf.d/"
    cp "build/files/graviteeio-apim-${componentName}.conf" "${TEMPLATE_DIR}/etc/nginx/conf.d/"
  fi
}

# Prepare Access Gateway packaging
build_access_gateway() {
  prepare_am_build -n "gateway" -b
  build_rpm -i "/etc/init.d/graviteeio-am-gateway" \
            -b "build/scripts/gateway" \
            -d "${DESC}: Access Gateway" \
            -n "${PKGNAME}-gateway" \
            -c "/opt/graviteeio/am/graviteeio-am-gateway-${VERSION_WITH_QUALIFIER}/config" \
            -a
}

build_management_api() {
  prepare_am_build -n "management-api" -b
  build_rpm -i "/etc/init.d/graviteeio-am-management-api" \
            -b "build/scripts/management-api" \
            -d "${DESC}: Management API" \
            -n "${PKGNAME}-management-api" \
            -c "/opt/graviteeio/am/graviteeio-am-management-api-${VERSION}/config" \
            -a
}

build_management_ui() {
  prepare_am_build -n "management-ui" -u
  build_rpm -b "build/scripts/management-ui" \
            -d "${DESC}: Management UI" \
            -n "${PKGNAME}-management-ui" \
            -x \
            -c "/opt/graviteeio/apim/graviteeio-am-management-ui-${VERSION_WITH_QUALIFIER}/constants.json" \
            -a
}

build_full() {
  # Dirty hack to avoid issues with FPM
  rm -fr build/skel/
  mkdir -p "${TEMPLATE_DIR}"

  build_rpm -x "${PKGNAME}-management-ui = ${VERSION}" \
            -x "${PKGNAME}-management-api = ${VERSION}" \
            -x "${PKGNAME}-gateway = ${VERSION}" \
            -d "${DESC}" \
            -n "${PKGNAME}"
}

build() {
  clean
  parse_version "$1"
  download "graviteeio-am-full-$1.zip" "/graviteeio-am/distributions"
  build_access_gateway
  build_management_api
  build_management_ui
  build_full
}

##################################################
# Startup
##################################################

build "$VERSION_WITH_QUALIFIER"
