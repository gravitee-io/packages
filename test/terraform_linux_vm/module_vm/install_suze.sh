#!/bin/bash

install_nginx() {
    sudo zypper addrepo -G -t yum -c 'http://nginx.org/packages/sles/15' nginx
    sudo rpm --import http://nginx.org/keys/nginx_signing.key
    sudo zypper -n install nginx
}

install_mongo() {
    sudo rpm --import https://www.mongodb.org/static/pgp/server-6.0.asc

    version=$(cut -d "=" -f2 <<< `cat /etc/os-release | grep VERSION_ID` | tr -d '"')
    if [[ $version = 12* ]]; then
      sudo zypper addrepo --gpgcheck "https://repo.mongodb.org/zypper/suse/12/mongodb-org/6.0/x86_64/" mongodb
    else
      sudo zypper addrepo --gpgcheck "https://repo.mongodb.org/zypper/suse/15/mongodb-org/6.0/x86_64/" mongodb
    fi
    
    sudo zypper -n install mongodb-org
    sudo systemctl start mongod
}

install_elasticsearch() {
    sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
    echo "[elasticsearch]
name=Elasticsearch repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md" | sudo tee /etc/zypp/repos.d/elasticsearch.repo > /dev/null
    sudo zypper modifyrepo --enable elasticsearch
    sudo zypper -n install elasticsearch
    sudo zypper modifyrepo --disable elasticsearch
    sudo sed "0,/xpack.security.enabled:.*/s/xpack.security.enabled:.*/xpack.security.enabled: false/" -i /etc/elasticsearch/elasticsearch.yml
    sudo systemctl start elasticsearch
}

install_openjdk() {
  version=$(cut -d "=" -f2 <<< `cat /etc/os-release | grep VERSION_ID` | tr -d '"')
  if [[ $version = 12* ]]; then
    sudo zypper addrepo https://download.opensuse.org/repositories/Java:Factory/SLE_12_SP5/Java:Factory.repo
    sudo zypper --gpg-auto-import-keys ref
    sudo zypper refresh
  fi

  sudo zypper -n install java-17-openjdk
}

install_prerequities() {
    install_openjdk
    install_nginx
    install_mongo
    install_elasticsearch
}

install_graviteeio_repository() {
    echo "[graviteeio]
    name=graviteeio
    baseurl=https://packagecloud.io/graviteeio/rpms/el/7/\$basearch
    gpgcheck=0
    enabled=1
    gpgkey=https://packagecloud.io/graviteeio/rpms/gpgkey
    sslverify=1
    sslcacert=/etc/pki/tls/certs/ca-bundle.crt
    metadata_expire=300
    type=rpm-md" | sudo tee /etc/zypp/repos.d/graviteeio.repo > /dev/null
}

install_graviteeio_from_repository() {
  install_graviteeio_repository

  sudo zypper -n install graviteeio-apim-4x

  sudo systemctl daemon-reload
  sudo systemctl start graviteeio-apim-gateway graviteeio-apim-rest-api
  http_response=$(curl -w "%{http_code}" -o /tmp/curl_body "http://169.254.169.254/latest/meta-data/public-ipv4")
  if [ $http_response == "200" ]; then
      sudo sed -i -e "s/localhost/$(cat /tmp/curl_body)/g" /opt/graviteeio/apim/management-ui/constants.json
      sudo sed -i -e "s;/portal;http://$(cat /tmp/curl_body):8083/portal;g" /opt/graviteeio/apim/portal-ui/assets/config.json
  fi
  sudo systemctl restart nginx
  echo "Graviteeio installation Done."
}

install_graviteeio_from_local_rpms() {
  for rpm in ~/*.rpm
  do
    echo "Installing ${rpm} ..."
    sudo zypper --non-interactive --no-gpg-checks install "${rpm}"
  done
  echo "Installation of RPMs done."

  sudo systemctl daemon-reload
  sudo systemctl start graviteeio-apim-gateway graviteeio-apim-rest-api

  echo "wait backend start"
  sleep 45 #wait backend start

  echo "run frontend"
  http_response=$(curl -w "%{http_code}" -o /tmp/curl_body "http://169.254.169.254/latest/meta-data/public-ipv4")
  if [ $http_response == "200" ]; then
      sudo sed -i -e "s/localhost/$(cat /tmp/curl_body)/g" /opt/graviteeio/apim/management-ui/constants.json
      sudo sed -i -e "s;/portal;http://$(cat /tmp/curl_body):8083/portal;g" /opt/graviteeio/apim/portal-ui/assets/config.json
  fi

  sudo systemctl restart nginx
  echo "Graviteeio installation Done."
}

help() {
  cat <<EOF
This script let you install GraviteeIO from local RPM or official published repo

usage : $0 [COMMAND]

COMMAND : (default: install_prerequities)
${COMMANDS}

exemple :
./install_redhat_graviteeio.sh install_prerequities

./install_redhat_graviteeio.sh install_graviteeio_from_repository

./install_redhat_graviteeio.sh install_graviteeio_from_local_rpms

EOF
}

### Default context ###
COMMANDS="$(sed -n '/^[a-z].*(){$/ s/(){//p' $0)"
COMMAND="install_prerequities"

### Parse args ###
if [[ -n "$1" ]]
then
  COMMAND="$1"
fi

### main ###
${COMMAND}
