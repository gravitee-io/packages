#!/bin/bash

#let script exit if a command fails
set -o errexit

#let script exit if an unsed variable is used
set -o nounset

declare VERSION_WITH_QUALIFIER=""
declare VERSION=""
declare RELEASE="1"
declare PKGNAME="graviteeio-apim"
declare LICENSE="Apache 2.0"
declare VENDOR="GraviteeSource"
declare URL="https://gravitee.io"
declare USER="gravitee"
declare ARCH="noarch"
declare DESC="Gravitee.io API Management 3.x"
declare MAINTAINER="David BRASSELY <david.brassely@graviteesource.com>"
declare DOCKER_WDIR="/tmp/fpm"
declare DOCKER_FPM="graviteeio/fpm"
declare TEMPLATE_DIR=""

parse_version() {
  declare GRAVITEEIO_QUALIFIER=""

  # parse version to determine if it is a pre release or not
  # More information about the versioning here:
  #  - https://fedoraproject.org/wiki/Package_Versioning_Examples
  #  - https://docs.fedoraproject.org/en-US/packaging-guidelines/Versioning/#_prerelease_versions

  VERSION=$(echo "$VERSION_WITH_QUALIFIER" | awk -F '-' '{print $1}') # 3.19.0

  GRAVITEEIO_QUALIFIER=$(echo "$VERSION_WITH_QUALIFIER" | awk -F '-' '{print $2}') # alpha.1 or empty
  if [ -n "$GRAVITEEIO_QUALIFIER" ]; then
    declare GRAVITEEIO_QUALIFIER_NAME=""
    declare GRAVITEEIO_QUALIFIER_VERSION=""

    GRAVITEEIO_QUALIFIER_NAME=$(echo "$GRAVITEEIO_QUALIFIER" | awk -F '.' '{print $1}')    # alpha or empty
    GRAVITEEIO_QUALIFIER_VERSION=$(echo "$GRAVITEEIO_QUALIFIER" | awk -F '.' '{print $2}') # 1  or empty

    # If there is a qualifier, it means that the version is a pre-release. So according to the documentation, release must be a number < 1 and of the form "0.x"
    RELEASE="0.$GRAVITEEIO_QUALIFIER_VERSION.$GRAVITEEIO_QUALIFIER_NAME"
  else
    # If there is no qualifier, it means that the version is a final release. So according to the documentation, release must be a number >= 1
    RELEASE="1"
  fi
}

clean() {
  rm -rf build/skel/*
  rm -f *.deb
  rm -f *.rpm
  rm -f *.tar.gz
}

# Download bundle
download() {
  local filename="graviteeio-full-${VERSION_WITH_QUALIFIER}.zip"
  rm -fr .staging
  mkdir .staging
  wget --progress=bar:force -P .staging https://download.gravitee.io/graviteeio-apim/distributions/${filename}
  wget -nv -P .staging "https://download.gravitee.io/graviteeio-apim/distributions/${filename}.sha1"
  cd .staging
  sha1sum -c ${filename}.sha1
  unzip ${filename}
  rm ${filename}
  rm ${filename}.sha1
  cd ..
}

# Prepare API Gateway packaging
build_api_gateway() {
  rm -fr build/skel/

  mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/apim
  cp -fr .staging/graviteeio-full-${VERSION_WITH_QUALIFIER}/graviteeio-apim-gateway-${VERSION_WITH_QUALIFIER} ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-gateway
  ln -sf build/skel/el7/opt/graviteeio/apim/graviteeio-apim-gateway ${TEMPLATE_DIR}/opt/graviteeio/apim/gateway
  mkdir -p ${TEMPLATE_DIR}/etc/systemd/system/
  cp build/files/systemd/graviteeio-apim-gateway.service ${TEMPLATE_DIR}/etc/systemd/system/

  mkdir -p ${TEMPLATE_DIR}/etc/init.d
  cp build/files/init.d/graviteeio-apim-gateway ${TEMPLATE_DIR}/etc/init.d

  docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
    --rpm-user ${USER} \
    --rpm-group ${USER} \
    --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
    --rpm-attr "0755,root,root:/etc/init.d/graviteeio-apim-gateway" \
    --directories /opt/graviteeio \
    --before-install build/scripts/gateway/preinst.rpm \
    --after-install build/scripts/gateway/postinst.rpm \
    --before-remove build/scripts/gateway/prerm.rpm \
    --after-remove build/scripts/gateway/postrm.rpm \
    --iteration ${RELEASE} \
    -C ${TEMPLATE_DIR} \
    -s dir -v ${VERSION} \
    --license "${LICENSE}" \
    --vendor "${VENDOR}" \
    --maintainer "${MAINTAINER}" \
    --architecture ${ARCH} \
    --url "${URL}" \
    --description "${DESC}: API Gateway" \
    --config-files /opt/graviteeio/apim/graviteeio-apim-gateway/config \
    --verbose \
    -n ${PKGNAME}-gateway-3x
}

build_rest_api() {
  rm -fr build/skel/

  mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/apim
  cp -fr .staging/graviteeio-full-${VERSION_WITH_QUALIFIER}/graviteeio-apim-rest-api-${VERSION_WITH_QUALIFIER} ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-rest-api
  ln -sf ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-rest-api ${TEMPLATE_DIR}/opt/graviteeio/apim/rest-api
  mkdir -p ${TEMPLATE_DIR}/etc/systemd/system/
  cp build/files/systemd/graviteeio-apim-rest-api.service ${TEMPLATE_DIR}/etc/systemd/system/

  mkdir -p ${TEMPLATE_DIR}/etc/init.d
  cp build/files/init.d/graviteeio-apim-rest-api ${TEMPLATE_DIR}/etc/init.d

  docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
    --rpm-user ${USER} \
    --rpm-group ${USER} \
    --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
    --rpm-attr "0755,root,root:/etc/init.d/graviteeio-apim-rest-api" \
    --directories /opt/graviteeio \
    --before-install build/scripts/rest-api/preinst.rpm \
    --after-install build/scripts/rest-api/postinst.rpm \
    --before-remove build/scripts/rest-api/prerm.rpm \
    --after-remove build/scripts/rest-api/postrm.rpm \
    --iteration ${RELEASE} \
    -C ${TEMPLATE_DIR} \
    -s dir -v ${VERSION} \
    --license "${LICENSE}" \
    --vendor "${VENDOR}" \
    --maintainer "${MAINTAINER}" \
    --architecture ${ARCH} \
    --url "${URL}" \
    --description "${DESC}: Management API" \
    --config-files /opt/graviteeio/apim/graviteeio-apim-rest-api/config \
    --verbose \
    -n ${PKGNAME}-rest-api-3x
}

build_management_ui() {
  rm -fr build/skel/

  mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/apim
  cp -fr .staging/graviteeio-full-${VERSION_WITH_QUALIFIER}/graviteeio-apim-console-ui-${VERSION_WITH_QUALIFIER} ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-console-ui
  ln -sf ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-console-ui ${TEMPLATE_DIR}/opt/graviteeio/apim/management-ui
  mkdir -p ${TEMPLATE_DIR}/etc/nginx/conf.d/
  cp build/files/graviteeio-apim-management-ui.conf ${TEMPLATE_DIR}/etc/nginx/conf.d/

  docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
    --rpm-user ${USER} \
    --rpm-group ${USER} \
    --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
    --directories /opt/graviteeio \
    --before-install build/scripts/management-ui/preinst.rpm \
    --after-install build/scripts/management-ui/postinst.rpm \
    --before-remove build/scripts/management-ui/prerm.rpm \
    --after-remove build/scripts/management-ui/postrm.rpm \
    --iteration ${RELEASE} \
    -C ${TEMPLATE_DIR} \
    -s dir -v ${VERSION} \
    --license "${LICENSE}" \
    --vendor "${VENDOR}" \
    --maintainer "${MAINTAINER}" \
    --architecture ${ARCH} \
    --url "${URL}" \
    --description "${DESC}: Management UI" \
    --depends nginx \
    --config-files /opt/graviteeio/apim/graviteeio-apim-console-ui/constants.json \
    --verbose \
    -n ${PKGNAME}-management-ui-3x
}

build_portal_ui() {
  rm -fr build/skel/

  mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/apim
  cp -fr .staging/graviteeio-full-${VERSION_WITH_QUALIFIER}/graviteeio-apim-portal-ui-${VERSION_WITH_QUALIFIER} ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-portal-ui
  ln -sf ${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-portal-ui ${TEMPLATE_DIR}/opt/graviteeio/apim/portal-ui
  mkdir -p ${TEMPLATE_DIR}/etc/nginx/conf.d/
  cp build/files/graviteeio-apim-portal-ui.conf ${TEMPLATE_DIR}/etc/nginx/conf.d/

  docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
    --rpm-user ${USER} \
    --rpm-group ${USER} \
    --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
    --directories /opt/graviteeio \
    --before-install build/scripts/portal-ui/preinst.rpm \
    --after-install build/scripts/portal-ui/postinst.rpm \
    --before-remove build/scripts/portal-ui/prerm.rpm \
    --after-remove build/scripts/portal-ui/postrm.rpm \
    --iteration ${RELEASE} \
    -C ${TEMPLATE_DIR} \
    -s dir -v ${VERSION} \
    --license "${LICENSE}" \
    --vendor "${VENDOR}" \
    --maintainer "${MAINTAINER}" \
    --architecture ${ARCH} \
    --url "${URL}" \
    --description "${DESC}: Portal UI" \
    --depends nginx \
    --config-files "${TEMPLATE_DIR}/opt/graviteeio/apim/graviteeio-apim-portal-ui/assets/" \
    --verbose \
    -n ${PKGNAME}-portal-ui-3x
}

build_full() {
  # Dirty hack to avoid issues with FPM
  rm -fr build/skel/
  mkdir -p ${TEMPLATE_DIR}

  docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
    --rpm-user ${USER} \
    --rpm-group ${USER} \
    --rpm-attr "0750,${USER},${USER}:/opt/graviteeio" \
    --iteration ${RELEASE} \
    -C ${TEMPLATE_DIR} \
    -s dir -v ${VERSION} \
    --license "${LICENSE}" \
    --vendor "${VENDOR}" \
    --maintainer "${MAINTAINER}" \
    --architecture ${ARCH} \
    --url "${URL}" \
    --description "${DESC}" \
    --depends "${PKGNAME}-portal-ui-3x = ${VERSION}" \
    --depends "${PKGNAME}-management-ui-3x = ${VERSION}" \
    --depends "${PKGNAME}-rest-api-3x = ${VERSION}" \
    --depends "${PKGNAME}-gateway-3x = ${VERSION}" \
    --verbose \
    -n ${PKGNAME}-3x
}

build() {
  clean
  parse_version
  download
  build_api_gateway
  build_rest_api
  build_management_ui
  build_portal_ui
  build_full
}

##################################################
# Startup
##################################################

while getopts ':v:l:' o; do
  case $o in
  v) VERSION_WITH_QUALIFIER=$OPTARG ;;
  h | *) usage ;;
  esac
done
shift $((OPTIND - 1))

TEMPLATE_DIR=build/skel/el

build
