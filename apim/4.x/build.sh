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
declare DESC="Gravitee.io API Management 4.x"
declare MAINTAINER="David BRASSELY <david.brassely@graviteesource.com>"
declare DOCKER_WDIR="/tmp/fpm"
declare DOCKER_FPM="graviteeio/fpm"
declare TEMPLATE_DIR=""

parse_version() {
  declare GRAVITEEIO_QUALIFIER=""

  # RPM has no notion of a pre-release, and RELEASE cannot stand in for one: it is only read when
  # two versions are equal, so it can rank 4.13.0-alpha.1 against 4.13.0 but never against 4.12.17.
  # The qualifier therefore belongs in VERSION, behind a tilde — the one token that sorts before
  # everything, including the empty string. Needs rpm >= 4.10; el/7 ships 4.11.3.
  #
  # A hotfix is the mirror case: it comes after the release it fixes, so its version stays bare and
  # RELEASE is what grows. Note that 1.hotfix.N and the plain integers are not two independent
  # spaces: a rebuild published as 4.12.17-2 outranks 4.12.17-1.hotfix.1 and would ship unfixed
  # content, so a release that already carries a hotfix has to be rebuilt inside the hotfix range.

  VERSION=$(echo "$VERSION_WITH_QUALIFIER" | awk -F '-' '{print $1}')              # 4.13.0
  GRAVITEEIO_QUALIFIER=$(echo "$VERSION_WITH_QUALIFIER" | awk -F '-' '{print $2}') # alpha.1, hotfix.2 or empty

  RELEASE="1"
  if [ -z "$GRAVITEEIO_QUALIFIER" ]; then
    return
  fi

  # The qualifier decides which side of the release the package lands on, so it is matched against
  # a closed vocabulary rather than sorted by a catch-all. Anything a catch-all would have to guess
  # about — a missing number, a spelling variant — is placed by accident, and -hotfix placed by
  # accident sorts below the release it fixes.
  case "$GRAVITEEIO_QUALIFIER" in
  hotfix.[0-9]*) RELEASE="1.${GRAVITEEIO_QUALIFIER}" ;;
  alpha.[0-9]* | beta.[0-9]* | rc.[0-9]* | milestone.[0-9]*) VERSION="${VERSION}~${GRAVITEEIO_QUALIFIER}" ;;
  *)
    echo "Cannot package '$VERSION_WITH_QUALIFIER': the qualifier must be alpha, beta, rc, milestone or hotfix, followed by a number." >&2
    exit 1
    ;;
  esac
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
  local path="graviteeio-apim/distributions/"
  # Any qualified version is uploaded to a folder of its own. RELEASE no longer says which, now
  # that a pre-release carries its qualifier in the version.
  if [[ "$VERSION_WITH_QUALIFIER" == *-* ]]; then
    path="pre-releases/graviteeio-apim/distributions/"
  fi
  rm -fr .staging
  mkdir .staging
  wget --progress=bar:force -P .staging https://download.gravitee.io/${path}${filename}
  wget -nv -P .staging "https://download.gravitee.io/${path}${filename}.sha1"
  cd .staging
  sha1sum -c ${filename}.sha1
  unzip -q ${filename}
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
    -n ${PKGNAME}-gateway-4x
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
    -n ${PKGNAME}-rest-api-4x
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
    -n ${PKGNAME}-management-ui-4x
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
    --config-files "/opt/graviteeio/apim/graviteeio-apim-portal-ui/assets/config.json" \
    --verbose \
    -n ${PKGNAME}-portal-ui-4x
}

build_full() {
  # Dirty hack to avoid issues with FPM
  rm -fr build/skel/
  mkdir -p ${TEMPLATE_DIR}

  # The dependencies below are pinned on the full EVR, not on the version alone. This package
  # carries no payload of its own, so an under-specified dependency is satisfied by whatever is
  # already installed — and a hotfix, whose version is the released one and whose release alone
  # moves, would install nothing at all.

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
    --depends "${PKGNAME}-portal-ui-4x = ${VERSION}-${RELEASE}" \
    --depends "${PKGNAME}-management-ui-4x = ${VERSION}-${RELEASE}" \
    --depends "${PKGNAME}-rest-api-4x = ${VERSION}-${RELEASE}" \
    --depends "${PKGNAME}-gateway-4x = ${VERSION}-${RELEASE}" \
    --verbose \
    -n ${PKGNAME}-4x
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
