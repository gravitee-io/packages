#!/bin/bash

# Import common scripts
. ../../common.sh

PKGNAME="graviteeio-apim"
DESC="Gravitee.io API Management 1.x"

prepare_apim_build() {
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
        echo "script usage: prepare_apim_build [-n componentName] [-u] [-b]" >&2
        exit 1
        ;;
    esac
  done
  shift $((OPTIND -1))

  rm -fr build/skel/

  mkdir -p "${TEMPLATE_DIR}/opt/graviteeio/apim"
  cp -fr ".staging/graviteeio-full-${VERSION_WITH_QUALIFIER}/graviteeio-${componentName}-${VERSION_WITH_QUALIFIER}" "${TEMPLATE_DIR}/opt/graviteeio/apim"
  ln -sf "${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-${componentName}-${VERSION_WITH_QUALIFIER}" "${TEMPLATE_DIR}/opt/graviteeio/apim/${componentName}"

  if [ -n "${isBack}" ]; then
    mkdir -p "${TEMPLATE_DIR}/etc/systemd/system/"
    cp "build/files/systemd/graviteeio-apim-${componentName}.service" "${TEMPLATE_DIR}/etc/systemd/system/"

    mkdir -p "${TEMPLATE_DIR}/etc/init.d"
    cp "build/files/init.d/graviteeio-apim-${componentName}" "${TEMPLATE_DIR}/etc/init.d"
  fi

  if [ -n "${isUI}" ]; then
    mkdir -p "${TEMPLATE_DIR}/etc/nginx/conf.d/"
    cp "build/files/graviteeio-apim-${componentName}.conf" "${TEMPLATE_DIR}/etc/nginx/conf.d/"
  fi
}


# Prepare API Gateway packaging
build_api_gateway() {
  prepare_apim_build -n "gateway" -b
  build_rpm -i "/etc/init.d/graviteeio-apim-gateway" \
            -b "build/scripts/gateway" \
            -d "${DESC}: API Gateway" \
            -n "${PKGNAME}-gateway" \
            -c "/opt/graviteeio/apim/graviteeio-gateway-${VERSION_WITH_QUALIFIER}/config" \
            -a
}

build_rest_api() {
  prepare_apim_build -n "management-api" -b

  build_rpm -i "/etc/init.d/graviteeio-apim-management-api" \
            -b "build/scripts/management-api" \
            -d "${DESC}: Management API" \
            -n "${PKGNAME}-management-api" \
            -c "/opt/graviteeio/apim/graviteeio-management-api-${VERSION_WITH_QUALIFIER}/config" \
            -a
}

build_management_ui() {
  prepare_apim_build -n "management-ui" -u

  build_rpm -b "build/scripts/management-ui" \
            -d "${DESC}: Management UI" \
            -n "${PKGNAME}-management-ui" \
            -x "nginx" \
            -c "/opt/graviteeio/apim/graviteeio-apim-management-ui-${VERSION_WITH_QUALIFIER}/constants.json" \
            -a
}

build_full() {
  # Dirty hack to avoid issues with FPM
  rm -fr build/skel/
  mkdir -p "${TEMPLATE_DIR}"

  build_rpm -x "${PKGNAME}-management-ui >= ${VERSION}" \
            -x "${PKGNAME}-management-api >= ${VERSION}" \
            -x "${PKGNAME}-gateway >= ${VERSION}" \
            -d "${DESC}" \
            -n "${PKGNAME}"
}

build() {
  clean
  parse_version "$1"
  download "graviteeio-full-$1.zip" "/graviteeio-apim/distributions"
  build_api_gateway
  build_management_api
  build_management_ui
  build_full
}

##################################################
# Startup
##################################################

build "$VERSION_WITH_QUALIFIER"
