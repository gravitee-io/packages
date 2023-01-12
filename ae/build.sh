#!/bin/bash

# Import common scripts
. ../common.sh

PKGNAME="graviteeio-ae"
DESC="Gravitee.io Alert Engine 1.x"

prepare_ae_build() {
  rm -fr build/skel/

  mkdir -p "${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION_WITH_QUALIFIER}"
  cp -fr ".staging/gravitee-ae-standalone-${VERSION_WITH_QUALIFIER}/*" "${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION_WITH_QUALIFIER}"
  ln -sf "${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION_WITH_QUALIFIER}" "${TEMPLATE_DIR}/opt/graviteeio/ae/engine"

  mkdir -p "${TEMPLATE_DIR}/etc/systemd/system/"
  cp "build/files/systemd/graviteeio-ae-engine.service" "${TEMPLATE_DIR}/etc/systemd/system/"

  mkdir -p "${TEMPLATE_DIR}/etc/init.d"
  cp "build/files/init.d/graviteeio-ae-engine" "${TEMPLATE_DIR}/etc/init.d"
}

# Prepare Alert Engine packaging
build_alert_engine() {
  prepare_ae_build
  build_rpm -i "/etc/init.d/graviteeio-ae-engine" \
            -b "build/scripts/engine" \
            -d "${DESC}: Alert Engine" \
            -n "${PKGNAME}-engine" \
            -c "/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION_WITH_QUALIFIER}/config" \
            -c "/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION_WITH_QUALIFIER}/license" \
            -a
}

build() {
  clean
  parse_version "$1"
  download "gravitee-ae-engine-$1.zip" "/graviteeio-ae/components"
  build_alert_engine
}

##################################################
# Startup
##################################################

build "$VERSION_WITH_QUALIFIER"
