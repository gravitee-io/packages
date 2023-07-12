#!/bin/bash

#let script exit if a command fails
set -o errexit

#let script exit if an unsed variable is used
set -o nounset

#Common variables
declare LICENSE="Apache 2.0"
declare VENDOR="GraviteeSource"
declare URL="https://gravitee.io"
declare USER="gravitee"
declare ARCH="noarch"
declare MAINTAINER="David BRASSELY <david.brassely@graviteesource.com>"
declare DOCKER_WDIR="/tmp/fpm"
declare DOCKER_FPM="graviteeio/fpm"
declare TEMPLATE_DIR="build/skel/el"


declare VERSION_WITH_QUALIFIER=""
declare VERSION=""
declare RELEASE=""

while getopts 'v:' OPTION; do
  case "$OPTION" in
    v)
      VERSION_WITH_QUALIFIER="$OPTARG"
      ;;
    ?)
      echo "script usage: ./build.sh [-v version]" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

if [ -z "${VERSION_WITH_QUALIFIER}" ]; then
  echo "script usage: ./build.sh [-v version]" >&2
  exit 1
fi

##
# Utility function to start the RPM build.
# Usage: `build_rpm [-i initDFile] [-b buildScriptDir] [-d componentDescription] [-n componentName] [-u addNginxDep] [-c configFilePath] [-a addDirectories]`
#
# Example: `build_rpm -i "/etc/init.d/graviteeio-apim-rest-api" -b "build/scripts/rest-api" -d "Management API" -n "rest-api-3x" -c "/opt/graviteeio/apim/graviteeio-apim-rest-api-3.19.0/config"`
##
build_rpm() {
  local initDFile
  local buildScriptDir
  local componentDescription
  local componentName
  local dependencies=()
  local configFilePath=()
  local addDirectories

  local OPTIND o
  while getopts 'i:b:d:n:x:c:a' o; do
    case "${o}" in
      i)
        initDFile="${OPTARG}"
        ;;
      b)
        buildScriptDir="${OPTARG}"
        ;;
      d)
        componentDescription="${OPTARG}"
        ;;
      n)
        componentName="${OPTARG}"
        ;;
      x)
        dependencies+=("${OPTARG}")
        ;;
      c)
        configFilePath+=("${OPTARG}")
        ;;
      a)
        addDirectories=true
        ;;
      ?)
        echo "script usage: build_rpm [-i initDFile] [-b buildScriptDir] [-d componentDescription] [-n componentName] [-x addNginxDep] [-c configFilePath] [-a addDirectories]" >&2
        exit 1
        ;;
    esac
  done
  shift $((OPTIND -1))


  # Base attributes
  local dockerAttributes=(--rm -v "${PWD}:${DOCKER_WDIR}" -w "${DOCKER_WDIR}" "${DOCKER_FPM}":rpm -t rpm)

  # RPM attributes
  dockerAttributes+=(--rpm-user "${USER}")
  dockerAttributes+=(--rpm-group "${USER}")
  dockerAttributes+=(--rpm-attr "0755,${USER},${USER}:/opt/graviteeio")
  if [ -n "${initDFile}" ]; then
    dockerAttributes+=(--rpm-attr "0755,root,root:${initDFile}")
  fi

  # Build scripts
  if [ -n "${buildScriptDir}" ]; then
    dockerAttributes+=(--before-install "${buildScriptDir}/preinst.rpm")
    dockerAttributes+=(--after-install "${buildScriptDir}/preinst.rpm")
    dockerAttributes+=(--before-remove "${buildScriptDir}/preinst.rpm")
    dockerAttributes+=(--after-remove "${buildScriptDir}/preinst.rpm")
  fi

  # Package attributes
  if [ -n "${addDirectories}" ]; then
    dockerAttributes+=(--directories /opt/graviteeio)
  fi
  dockerAttributes+=(--iteration "${RELEASE}")
  dockerAttributes+=(-C "${TEMPLATE_DIR}")
  dockerAttributes+=(-s dir -v "${VERSION}")
  dockerAttributes+=(--license "${LICENSE}")
  dockerAttributes+=(--vendor "${VENDOR}")
  dockerAttributes+=(--maintainer "${MAINTAINER}")
  dockerAttributes+=(--architecture "${ARCH}")
  dockerAttributes+=(--url "${URL}")
  dockerAttributes+=(--description  "${componentDescription}")

  for dependency in "${dependencies[@]}"; do
    dockerAttributes+=(--depends "${dependency}")
  done

  for config in "${configFilePath[@]}"; do
    dockerAttributes+=(--config-files "$config")
  done
  dockerAttributes+=(--verbose)
  dockerAttributes+=(-n "${componentName}")

  echo "Building RPM package for ${componentName}...:" "${dockerAttributes[@]}"

  docker run "${dockerAttributes[@]}"
}

clean() {
  rm -rf build/skel/*
  rm -f ./*.deb
  rm -f ./*.rpm
  rm -f ./*.tar.gz
}

##
# Utility function to download product bundle.
# Usage: `download [fileName] [srcPath]`
#  - fileName is the name of the full zip bundle
#  - srcPath is the path to the bundle on the download server. MUST start with '/'
#
# Example: `download "graviteeio-full-3.19.0.zip" "/graviteeio-apim/distributions"`
##
download() {
  local filename=$1
  local srcPath=$2
  rm -fr .staging
  mkdir .staging
  wget --progress=bar:force -P .staging "https://download.gravitee.io${srcPath}/${filename}"
  wget -nv -P .staging "https://download.gravitee.io${srcPath}/${filename}.sha1"
  cd .staging ; sha1sum -c "${filename}.sha1" ; unzip "${filename}" ; rm "${filename}" ; rm "${filename}.sha1" ; cd ..
}

##
# Utility function to parse a version into 2 environment variables.
# `parse_version 3.19.0` will put:
#  - 3.19.0 in $VERSION
#  - 1 in $RELEASE    <-- it's a final release
#
# `parse_version 3.19.0-alpha.2` will put:
#  - 3.19.0 in $VERSION
#  - 0.2.alpha in $RELEASE    <-- it's a pre-release
##
parse_version() {
  declare GRAVITEEIO_QUALIFIER=""

  # parse version to determine if it is a pre release or not
  # More information about the versioning here:
  #  - https://fedoraproject.org/wiki/Package_Versioning_Examples
  #  - https://docs.fedoraproject.org/en-US/packaging-guidelines/Versioning/#_prerelease_versions

  VERSION=$(echo "$1" | awk -F '-' '{print $1}')    # 3.19.0

  GRAVITEEIO_QUALIFIER=$(echo "$1" | awk -F '-' '{print $2}')  # alpha.1 or empty
  if [ -n "$GRAVITEEIO_QUALIFIER" ]; then
    declare GRAVITEEIO_QUALIFIER_NAME=""
    declare GRAVITEEIO_QUALIFIER_VERSION=""

    GRAVITEEIO_QUALIFIER_NAME=$(echo "$GRAVITEEIO_QUALIFIER" | awk -F '.' '{print $1}')          # alpha or empty
    GRAVITEEIO_QUALIFIER_VERSION=$(echo "$GRAVITEEIO_QUALIFIER" | awk -F '.' '{print $2}')       # 1  or empty

    # If there is a qualifier, it means that the version is a pre-release. So according to the documentation, release must be a number < 1 and of the form "0.x"
    RELEASE="0.$GRAVITEEIO_QUALIFIER_VERSION.$GRAVITEEIO_QUALIFIER_NAME"
  else
    # If there is no qualifier, it means that the version is a final release. So according to the documentation, release must be a number >= 1
    RELEASE="1"
  fi
}