#!/bin/bash

#let script exit if a command fails
set -o errexit

#let script exit if an unsed variable is used
set -o nounset

declare VERSION=""
declare PKGNAME="graviteeio-apim"
declare LICENSE="Apache 2.0"
declare VENDOR="GraviteeSource"
declare URL="https://gravitee.io"
declare RELEASE="0"
declare USER="gravitee"
declare ARCH="noarch"
declare DESC="Gravitee.io API Management"
declare MAINTAINER="David BRASSELY <david.brassely@graviteesource.com>"
declare DOCKER_WDIR="/tmp/fpm"
declare DOCKER_FPM="graviteeio/fpm"

clean() {
	rm -rf build/skel/*
	rm -f *.deb
	rm -f *.rpm
	rm -f *.tar.gz
}

# Download bundle
download() {
	local filename="graviteeio-full-${VERSION}.zip"
	rm -fr .staging
	mkdir .staging
	wget --progress=bar:force -P .staging https://download.gravitee.io/graviteeio-apim/distributions/${filename}
	wget -nv -P .staging "https://download.gravitee.io/graviteeio-apim/distributions/${filename}.sha1"
	cd .staging ; sha1sum -c ${filename}.sha1 ; unzip ${filename} ; rm ${filename} ; rm ${filename}.sha1 ; cd ..
}

# Prepare API Gateway packaging
build_api_gateway() {
	rm -fr build/skel/

	mkdir -p build/skel/el7/opt/graviteeio/apim
	cp -fr .staging/graviteeio-full-${VERSION}/graviteeio-gateway-${VERSION} build/skel/el7/opt/graviteeio/apim
	ln -sf build/skel/el7/opt/graviteeio/apim/graviteeio-gateway-${VERSION} build/skel/el7/opt/graviteeio/apim/gateway

	mkdir -p build/skel/el7/etc/systemd/system/
	cp build/files/graviteeio-apim-gateway.service build/skel/el7/etc/systemd/system/

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
		--rpm-user ${USER} \
          	--rpm-group ${USER} \
          	--rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
          	--directories /opt/graviteeio \
        	--before-install build/scripts/gateway/preinst.rpm \
        	--after-install build/scripts/gateway/postinst.rpm \
        	--before-remove build/scripts/gateway/prerm.rpm \
        	--after-remove build/scripts/gateway/postrm.rpm \
                --iteration ${RELEASE}.el7 \
                -C build/skel/el7 \
		-s dir -v ${VERSION}  \
  		--license "${LICENSE}" \
  		--vendor "${VENDOR}" \
  		--maintainer "${MAINTAINER}" \
  		--architecture ${ARCH} \
  		--url "${URL}" \
  		--description  "${DESC}: API Gateway" \
  		--depends java-1.8.0-openjdk \
  		--config-files build/skel/el7/opt/graviteeio/apim/graviteeio-gateway-${VERSION}/config \
  		--verbose \
		-n ${PKGNAME}-gateway
}

build_management_api() {
	rm -fr build/skel/
	
	mkdir -p build/skel/el7/opt/graviteeio/apim
        cp -fr .staging/graviteeio-full-${VERSION}/graviteeio-management-api-${VERSION} build/skel/el7/opt/graviteeio/apim
	ln -sf build/skel/el7/opt/graviteeio/apim/graviteeio-management-api-${VERSION} build/skel/el7/opt/graviteeio/apim/management-api

	mkdir -p build/skel/el7/etc/systemd/system/
	cp build/files/graviteeio-apim-management-api.service build/skel/el7/etc/systemd/system/

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
                --rpm-user ${USER} \
                --rpm-group ${USER} \
                --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
                --directories /opt/graviteeio \
                --before-install build/scripts/management-api/preinst.rpm \
                --after-install build/scripts/management-api/postinst.rpm \
                --before-remove build/scripts/management-api/prerm.rpm \
                --after-remove build/scripts/management-api/postrm.rpm \
                --iteration ${RELEASE}.el7 \
                -C build/skel/el7 \
                -s dir -v ${VERSION}  \
                --license "${LICENSE}" \
                --vendor "${VENDOR}" \
                --maintainer "${MAINTAINER}" \
                --architecture ${ARCH} \
                --url "${URL}" \
                --description  "${DESC}: Management API" \
                --depends java-1.8.0-openjdk \
                --config-files build/skel/el7/opt/graviteeio/apim/graviteeio-management-api-${VERSION}/config \
                --verbose \
                -n ${PKGNAME}-management-api
}

build_management_ui() {
	rm -fr build/skel/

	mkdir -p build/skel/el7/opt/graviteeio/apim
        cp -fr .staging/graviteeio-full-${VERSION}/graviteeio-management-ui-${VERSION} build/skel/el7/opt/graviteeio/apim
	ln -sf build/skel/el7/opt/graviteeio/apim/graviteeio-management-ui-${VERSION} build/skel/el7/opt/graviteeio/apim/management-ui

	mkdir -p build/skel/el7/etc/nginx/default.d/
	cp build/files/graviteeio-management-ui.conf build/skel/el7/etc/nginx/default.d/

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
                --rpm-user ${USER} \
                --rpm-group ${USER} \
                --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
                --directories /opt/graviteeio \
		--before-install build/scripts/management-ui/preinst.rpm \
                --after-install build/scripts/management-ui/postinst.rpm \
                --before-remove build/scripts/management-ui/prerm.rpm \
                --after-remove build/scripts/management-ui/postrm.rpm \
                --iteration ${RELEASE}.el7 \
                -C build/skel/el7 \
                -s dir -v ${VERSION}  \
                --license "${LICENSE}" \
                --vendor "${VENDOR}" \
                --maintainer "${MAINTAINER}" \
                --architecture ${ARCH} \
                --url "${URL}" \
                --description  "${DESC}: Management UI" \
                --depends nginx \
		--config-files build/skel/el7/opt/graviteeio/apim/graviteeio-management-ui-${VERSION}/constants.json \
                --verbose \
                -n ${PKGNAME}-management-ui
}

build_full() {
	# Dirty hack to avoid issues with FPM
	rm -fr build/skel/
        mkdir -p build/skel/el7
	#touch build/skel/el7/.empty

	docker run --rm -v "${PWD}:${DOCKER_WDIR}" -w ${DOCKER_WDIR} ${DOCKER_FPM}:rpm -t rpm \
                --rpm-user ${USER} \
                --rpm-group ${USER} \
                --rpm-attr "0755,${USER},${USER}:/opt/graviteeio" \
                --iteration ${RELEASE}.el7 \
		-C build/skel/el7 \
                -s dir -v ${VERSION}  \
                --license "${LICENSE}" \
                --vendor "${VENDOR}" \
                --maintainer "${MAINTAINER}" \
                --architecture ${ARCH} \
                --url "${URL}" \
                --description  "${DESC}" \
                --depends "${PKGNAME}-management-ui >= ${VERSION}" \
		--depends "${PKGNAME}-management-api >= ${VERSION}" \
		--depends "${PKGNAME}-gateway >= ${VERSION}" \
                --verbose \
                -n ${PKGNAME}
}

build() {
	clean
	download
	build_api_gateway
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

build
