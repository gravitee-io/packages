#!/bin/bash

#let script exit if a command fails
set -o errexit

#let script exit if an unsed variable is used
set -o nounset

declare VERSION=""
declare PKGNAME="graviteeio-ae"
declare LICENSE="Apache 2.0"
declare VENDOR="GraviteeSource"
declare URL="https://gravitee.io"
declare RELEASE="0"
declare USER="gravitee"
declare ARCH="noarch"
declare DESC="Gravitee.io Alert Engine 1.x"
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
	local filename="gravitee-ae-engine-${VERSION}.zip"
	rm -fr .staging
	mkdir .staging
	wget --progress=bar:force -P .staging https://download.gravitee.io/graviteeio-ae/components/${filename}
	wget -nv -P .staging "https://download.gravitee.io/graviteeio-ae/components/${filename}.sha1"
	cd .staging ; sha1sum -c ${filename}.sha1 ; unzip ${filename} ; rm ${filename} ; rm ${filename}.sha1 ; cd ..
}

# Prepare Alert Engine packaging
build_alert_engine() {
	rm -fr build/skel/

	mkdir -p ${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION}
	cp -fr .staging/gravitee-ae-standalone-${VERSION}/* ${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION}
	ln -sf ${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION} ${TEMPLATE_DIR}/opt/graviteeio/ae/engine

	mkdir -p ${TEMPLATE_DIR}/etc/systemd/system/
    cp build/files/systemd/graviteeio-ae-engine.service ${TEMPLATE_DIR}/etc/systemd/system/

    mkdir -p ${TEMPLATE_DIR}/etc/init.d
    cp build/files/init.d/graviteeio-ae-engine ${TEMPLATE_DIR}/etc/init.d

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
		--rpm-user ${USER} \
          	--rpm-group ${USER} \
          	--rpm-attr "0750,${USER},${USER}:/opt/graviteeio" \
			--rpm-attr "0755,root,root:/etc/init.d/graviteeio-ae-engine" \
          	--directories /opt/graviteeio \
        	--before-install build/scripts/engine/preinst.rpm \
        	--after-install build/scripts/engine/postinst.rpm \
        	--before-remove build/scripts/engine/prerm.rpm \
        	--after-remove build/scripts/engine/postrm.rpm \
                --iteration ${RELEASE} \
                -C ${TEMPLATE_DIR} \
		-s dir -v ${VERSION}  \
  		--license "${LICENSE}" \
  		--vendor "${VENDOR}" \
  		--maintainer "${MAINTAINER}" \
  		--architecture ${ARCH} \
  		--url "${URL}" \
  		--description  "${DESC}: Alert Engine" \
  		--config-files ${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION}/config \
		--config-files ${TEMPLATE_DIR}/opt/graviteeio/ae/graviteeio-ae-engine-${VERSION}/license \
  		--verbose \
		-n ${PKGNAME}-engine
}

build() {
	clean
	download
	build_alert_engine
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
