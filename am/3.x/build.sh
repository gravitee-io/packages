#!/bin/bash

#let script exit if a command fails
set -o errexit

#let script exit if an unsed variable is used
set -o nounset

declare VERSION=""
declare PKGNAME="graviteeio-am"
declare LICENSE="Apache 2.0"
declare VENDOR="GraviteeSource"
declare URL="https://gravitee.io"
declare RELEASE="0"
declare USER="gravitee"
declare ARCH="noarch"
declare DESC="Gravitee.io Access Management 3.x"
declare MAINTAINER="David BRASSELY <david.brassely@graviteesource.com>"
declare DOCKER_WDIR="/tmp/fpm"
declare DOCKER_FPM="graviteeio/fpm"
declare TEMPLATE_DIR=""

clean() {
	rm -rf build/skel/*
	rm -f *.deb
	rm -f *.rpm
	rm -f *.tar.gz
}

# Download bundle
download() {
	local filename="graviteeio-am-full-${VERSION}.zip"
	rm -fr .staging
	mkdir .staging
	wget --progress=bar:force -P .staging https://download.gravitee.io/graviteeio-am/distributions/${filename}
	wget -nv -P .staging "https://download.gravitee.io/graviteeio-am/distributions/${filename}.sha1"
	cd .staging ; sha1sum -c ${filename}.sha1 ; unzip ${filename} ; rm ${filename} ; rm ${filename}.sha1 ; cd ..
}

# Prepare Access Gateway packaging
build_access_gateway() {
	rm -fr build/skel/

	mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/am
	cp -fr .staging/graviteeio-am-full-${VERSION}/graviteeio-am-gateway-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/am
	ln -sf ${TEMPLATE_DIR}/opt/graviteeio/am/graviteeio-am-gateway-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/am/gateway

	mkdir -p ${TEMPLATE_DIR}/etc/systemd/system/
        cp build/files/systemd/graviteeio-am-gateway.service ${TEMPLATE_DIR}/etc/systemd/system/

        mkdir -p ${TEMPLATE_DIR}/etc/init.d
        cp build/files/init.d/graviteeio-am-gateway ${TEMPLATE_DIR}/etc/init.d

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
            --rpm-user ${USER} \
            --rpm-group ${USER} \
            --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
            --rpm-attr "0755,root,root:/etc/init.d/graviteeio-am-gateway" \
            --directories /opt/graviteeio \
            --before-install build/scripts/gateway/preinst.rpm \
            --after-install build/scripts/gateway/postinst.rpm \
            --before-remove build/scripts/gateway/prerm.rpm \
            --after-remove build/scripts/gateway/postrm.rpm \
            --iteration ${RELEASE} \
            -C ${TEMPLATE_DIR} \
            -s dir -v ${VERSION}  \
            --license "${LICENSE}" \
            --vendor "${VENDOR}" \
            --maintainer "${MAINTAINER}" \
            --architecture ${ARCH} \
            --url "${URL}" \
            --description  "${DESC}: Access Gateway" \
            --config-files /opt/graviteeio/am/graviteeio-am-gateway-${VERSION}/config \
            --verbose \
            -n ${PKGNAME}-gateway-3x
}

build_management_api() {
	rm -fr build/skel/
	
	mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/am
        cp -fr .staging/graviteeio-am-full-${VERSION}/graviteeio-am-management-api-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/am
	ln -sf ${TEMPLATE_DIR}/opt/graviteeio/am/graviteeio-am-management-api-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/am/management-api

        mkdir -p ${TEMPLATE_DIR}/etc/systemd/system/
	cp build/files/systemd/graviteeio-am-management-api.service ${TEMPLATE_DIR}/etc/systemd/system/

        mkdir -p ${TEMPLATE_DIR}/etc/init.d
        cp build/files/init.d/graviteeio-am-management-api ${TEMPLATE_DIR}/etc/init.d

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
            --rpm-user ${USER} \
            --rpm-group ${USER} \
            --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
            --rpm-attr "0755,root,root:/etc/init.d/graviteeio-am-management-api" \
            --directories /opt/graviteeio \
            --before-install build/scripts/management-api/preinst.rpm \
            --after-install build/scripts/management-api/postinst.rpm \
            --before-remove build/scripts/management-api/prerm.rpm \
            --after-remove build/scripts/management-api/postrm.rpm \
            --iteration ${RELEASE} \
            -C ${TEMPLATE_DIR} \
            -s dir -v ${VERSION}  \
            --license "${LICENSE}" \
            --vendor "${VENDOR}" \
            --maintainer "${MAINTAINER}" \
            --architecture ${ARCH} \
            --url "${URL}" \
            --description  "${DESC}: Management API" \
            --config-files /opt/graviteeio/am/graviteeio-am-management-api-${VERSION}/config \
            --verbose \
            -n ${PKGNAME}-management-api-3x
}

build_management_ui() {
	rm -fr build/skel/

	mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/am
        cp -fr .staging/graviteeio-am-full-${VERSION}/graviteeio-am-management-ui-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/am
	ln -sf ${TEMPLATE_DIR}/opt/graviteeio/am/graviteeio-am-management-ui-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/am/management-ui

	mkdir -p ${TEMPLATE_DIR}/etc/nginx/conf.d/
	cp build/files/graviteeio-am-management-ui.conf ${TEMPLATE_DIR}/etc/nginx/conf.d/

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
            -s dir -v ${VERSION}  \
            --license "${LICENSE}" \
            --vendor "${VENDOR}" \
            --maintainer "${MAINTAINER}" \
            --architecture ${ARCH} \
            --url "${URL}" \
            --description  "${DESC}: Management UI" \
            --depends nginx \
            --config-files /opt/graviteeio/am/graviteeio-am-management-ui-${VERSION}/constants.json \
            --verbose \
            -n ${PKGNAME}-management-ui-3x
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
            -s dir -v ${VERSION}  \
            --license "${LICENSE}" \
            --vendor "${VENDOR}" \
            --maintainer "${MAINTAINER}" \
            --architecture ${ARCH} \
            --url "${URL}" \
            --description  "${DESC}" \
            --depends "${PKGNAME}-management-ui-3x = ${VERSION}" \
            --depends "${PKGNAME}-management-api-3x = ${VERSION}" \
            --depends "${PKGNAME}-gateway-3x = ${VERSION}" \
            --verbose \
            -n ${PKGNAME}-3x
}

build() {
	clean
	download
	build_access_gateway
	build_management_api
	build_management_ui
	build_full
}

##################################################
# Startup
##################################################

while getopts ':v:' o
do
    case $o in
    v) VERSION=$OPTARG ;;
    h|*) usage ;;
    esac
done
shift $((OPTIND-1))

TEMPLATE_DIR=build/skel/el

build
