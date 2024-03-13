#!/bin/bash

install_nginx(){
    sudo yum install -y nginx
}

install_mongo(){
    local mongo_version="7.0"
    echo "[mongodb-org-${mongo_version}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/${mongo_version}/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-${mongo_version}.asc" | sudo tee "/etc/yum.repos.d/mongodb-org-${mongo_version}.repo" > /dev/null

    sudo yum install -y mongodb-org
    sudo systemctl start mongod
}

install_elasticsearch(){
    echo "[elastic-8.x]
name=Elastic repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=0
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md" | sudo tee /etc/yum.repos.d/elasticsearch.repo > /dev/null
    sudo yum install -y elasticsearch
    sudo sed "0,/xpack.security.enabled:.*/s/xpack.security.enabled:.*/xpack.security.enabled: false/" -i /etc/elasticsearch/elasticsearch.yml
    sudo systemctl start elasticsearch
}

install_openjdk(){
    if [[ "$os" == "centos" && "$version" -lt 8 ]]
    then
      # @see https://www.oracle.com/java/technologies/downloads/#java17
      curl -O 'https://download.oracle.com/java/17/latest/jdk-17_linux-x64_bin.rpm'
      curl -O 'https://download.oracle.com/java/17/latest/jdk-17_linux-x64_bin.rpm.sha256'
      echo " jdk-17_linux-x64_bin.rpm" >> jdk-17_linux-x64_bin.rpm.sha256
      sha256sum -c jdk-17_linux-x64_bin.rpm.sha256 || exit 1

      sudo yum install -y jdk-17_linux-x64_bin.rpm
    else
      sudo yum install -y java-17-openjdk-devel
    fi

    java -version
}

install_tools(){
    os=`cat /etc/redhat-release  | awk '{ print tolower($1) }'`
    version=$(awk -F'=' '/VERSION_ID/{ gsub(/"/,""); print $2}' /etc/os-release | cut -d. -f1)
    echo "Detect version: $os/$version"

    if [[ "$os" == "centos" && "$version" -eq 8 ]]
    then
        echo "Update Centos Stream"
        sudo sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
        sudo sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
        sudo yum update -y
    fi

    if [[ "$version" -lt 8 ]]
    then
        echo "Install specific tools for RHEL < 8"
        sudo yum install -y epel-release
    fi

    sudo yum install -y policycoreutils-python-utils
}

install_graviteeio_repository(){
    echo "[graviteeio]
name=graviteeio
baseurl=https://packagecloud.io/graviteeio/rpms/el/7/\$basearch
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/graviteeio/rpms/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300" | sudo tee /etc/yum.repos.d/graviteeio.repo > /dev/null
    sudo yum -q makecache -y --disablerepo='*' --enablerepo='graviteeio'
}

open_ui_ports(){
  ui_port=$(sudo semanage port -l | grep 8084 | wc -l)
  if [[ "$ui_port" -eq 0 ]]
  then
      sudo semanage port -a -t http_port_t -p tcp 8084
  else
      sudo semanage port -m -t http_port_t -p tcp 8084
  fi

  portal_port=$(sudo semanage port -l | grep 8085 | wc -l)
  if [[ "$portal_port" -eq 0 ]]
  then
      sudo semanage port -a -t http_port_t -p tcp 8085
  else
      sudo semanage port -m -t http_port_t -p tcp 8085
  fi
}

get_current_public_ip() {
  local public_ip

  public_ip="$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface?api-version=2021-02-01&format=json" | jq -r '.[].ipv4.ipAddress[].publicIpAddress')"
  if echo -n "${public_ip}" | grep -q -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
  then
    echo "${public_ip}"
    return 0
  fi

  public_ip="$(curl -s 'https://ipv4.seeip.org')"
  if echo -n "${public_ip}" | grep -q -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
  then
    echo "${public_ip}"
    return 0
  fi

  return 1
}

configure_frontend(){
  local public_ip="$1"
  if [[ -z "${public_ip}" ]]
  then
    echo "Missing IP argument." >&2
    return 1
  fi
  sudo sed -i "/\"baseURL\": /{s#\"baseURL\": \".*\"#\"baseURL\": \"http://${public_ip}:8083/management\"#}" /opt/graviteeio/apim/management-ui/constants.json
  sudo sed -i "/\"baseURL\": /{s#\"baseURL\": \".*\"#\"baseURL\": \"http://${public_ip}:8083/portal\"#}" /opt/graviteeio/apim/portal-ui/assets/config.json
}

install_graviteeio_from_repository(){
  local specific_version="${1}"
  if [[ -n "${specific_version}" ]]; then specific_version="-${specific_version}-1"; fi

  install_graviteeio_repository

  sudo yum install -y "graviteeio-apim-4x${specific_version}"
  echo "Installation of RPMs done."

  sudo systemctl daemon-reload
  sudo systemctl start graviteeio-apim-gateway graviteeio-apim-rest-api

  echo "wait backend start"
  sleep 45 #wait backend start

  echo "run frontend"
#  configure_frontend "$(get_current_public_ip)"
  configure_frontend "localhost"

  open_ui_ports

  sudo systemctl restart nginx
  echo "Graviteeio installation Done."
}

install_graviteeio_from_local_rpms(){
  local rpms_path="${1:-${HOME}}"
  for rpm in "${rpms_path}"/*.rpm
  do
    echo "Installing ${rpm} ..."
    sudo yum install -y "${rpm}"
  done
  echo "Installation of RPMs done."
  sudo systemctl daemon-reload
  sudo systemctl restart graviteeio-apim-gateway graviteeio-apim-rest-api

  echo "wait backend start"
  sleep 45 #wait backend start

  echo "run frontend"
  configure_frontend "localhost"

  open_ui_ports

  sudo systemctl restart nginx
  echo "Graviteeio installation Done."
}

setup_license(){
  if [[ ! -f ~/license.key ]]
  then
    echo "~/license.key not found" >&2
    return 1
  fi

  sudo cp ~/license.key /opt/graviteeio/
  sudo chown gravitee: /opt/graviteeio/license.key

  for component in "gateway" "rest-api"
  do
    sudo mkdir -p "/opt/graviteeio/apim/graviteeio-apim-${component}/license"
    sudo ln -s /opt/graviteeio/license.key "/opt/graviteeio/apim/graviteeio-apim-${component}/license/license.key"
    sudo chown -R gravitee: "/opt/graviteeio/apim/graviteeio-apim-${component}/license"
  done
}

install_prerequities(){
    install_tools
    install_openjdk
    install_nginx
    install_mongo
    install_elasticsearch
}

test_graviteeio(){
  echo "Test backend gateway"
  curl --user "admin:adminadmin" "http://localhost:18082/_node"
  echo ""

  echo "Test backend rest-api"
  curl --user 'admin:admin' "http://localhost:8083/management/organizations/DEFAULT/environments/DEFAULT/"
  echo ""

  echo "Test Console UI"
  curl -s 'http://localhost:8084/build.json'
  echo "---"
  curl -s 'http://localhost:8084/' | grep 'gravitee.*-loader'
  echo ""

  echo "Test Portal UI"
  curl -s 'http://localhost:8085/' | grep '<title>Gravitee.io Portal</title>'
  echo ""
}

help(){
  cat <<EOF
This script let you install GraviteeIO from local RPM or official published repo

usage : $0 [COMMAND]

COMMAND : (default: install_prerequities)
${COMMANDS}

exemple :
./install_redhat_graviteeio.sh install_prerequities

./install_redhat_graviteeio.sh install_graviteeio_from_repository
./install_redhat_graviteeio.sh install_graviteeio_from_repository 4.2.6

./install_redhat_graviteeio.sh install_graviteeio_from_local_rpms
./install_redhat_graviteeio.sh install_graviteeio_from_local_rpms /path/to/rpms/folder

./install_redhat_graviteeio.sh test_graviteeio

EOF
}

### Default context ###
COMMANDS="$(sed -n '/^[a-z].*(){$/ s/(){//p' $0)"
COMMAND="install_prerequities"

### Parse args ###
if [[ -n "$1" ]]
then
  COMMAND="$1"
  shift
fi

### main ###
${COMMAND} $@
