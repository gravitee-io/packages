#!/usr/bin/env bash
set -euo pipefail

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
    sudo systemctl daemon-reload
    sudo systemctl enable elasticsearch.service
    sudo systemctl start elasticsearch
}

install_openjdk(){
    local version="${1:-21}"

    case $version in
      21)
        if [[ "$os" == "centos" && "$version" -lt 8 ]]
        then
          # @see https://www.oracle.com/java/technologies/downloads/#java17
          curl -O 'https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.rpm'
          curl -O 'https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.rpm.sha256'
          echo " jdk-21_linux-x64_bin.rpm" >> jdk-21_linux-x64_bin.rpm.sha256
          sha256sum -c jdk-21_linux-x64_bin.rpm.sha256 || exit 1

          sudo yum install -y jdk-21_linux-x64_bin.rpm
        else
          sudo yum install -y java-21-openjdk-devel
        fi
      ;;
      17)
        if [[ "$os" == "centos" && "$version" -lt 8 ]]
        then
          # @see https://www.oracle.com/java/technologies/downloads/#java17
          curl -O 'https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.rpm'
          curl -O 'https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.rpm.sha256'
          echo " jdk-17.0.12_linux-x64_bin.rpm" >> jdk-17.0.12_linux-x64_bin.rpm.sha256
          sha256sum -c jdk-17.0.12_linux-x64_bin.rpm.sha256 || exit 1

          sudo yum install -y jdk-17.0.12_linux-x64_bin.rpm
        else
          sudo yum install -y java-17-openjdk-devel
        fi
      ;;
      *)
        echo "ERROR: install_openjdk version $version is not possible - install manually" >&2
        exit 1
      ;;
    esac

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
  # https://packagecloud.io/docs#rpm_any
    echo "[graviteeio]
name=graviteeio
baseurl=https://packagecloud.io/graviteeio/nightly/el/7/\$basearch
gpgcheck=1
repo_gpgcheck=1
enabled=1
gpgkey=https://packagecloud.io/graviteeio/nightly/gpgkey,https://packagecloud.io/graviteeio/nightly/gpgkey/graviteeio-nightly-319791EF7A93C060.pub.gpg
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300" | sudo tee /etc/yum.repos.d/graviteeio.repo > /dev/null
    sudo yum --quiet makecache --assumeyes --disablerepo='*' --enablerepo='graviteeio'
}

open_apim_ports(){
  echo "Use semanage port to open port 8084 (console) and 8085 (portal) on SE Linux."
  local port_number
  for port_number in 8084 8085
  do
    if sudo semanage port -l | grep http_port_t | grep -q "${port_number}"
    then
      echo "SE Linux update right for port ${port_number}"
      sudo semanage port -m -t http_port_t -p tcp "${port_number}"
    else
      echo "SE Linux open port ${port_number}"
      sudo semanage port -a -t http_port_t -p tcp "${port_number}"
    fi
  done

  # @see: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/using-and-configuring-firewalld_configuring-and-managing-networking#customizing-firewall-settings-for-a-specific-zone-to-enhance-security_working-with-firewalld-zones
  if (command -v firewall-cmd > /dev/null) && ! (sudo firewall-cmd --list-ports | grep -q '8082-8085/tcp')
  then
    echo "firewall detected - open port range: 8082-8085/tcp"
    sudo firewall-cmd --add-port=8082-8085/tcp
  fi
}

get_current_public_ip() {
  local public_ip

  #case of an Azure VM
  public_ip="$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface?api-version=2021-02-01&format=json" | jq -r '.[].ipv4.ipAddress[].publicIpAddress')"
  if echo -n "${public_ip}" | grep -q -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
  then
    echo "${public_ip}"
    return 0
  fi

  #case of an AWS EC2 VM
  public_ip="$(curl -s "http://169.254.169.254/latest/meta-data/public-ipv4")"
  if echo -n "${public_ip}" | grep -q -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
  then
    echo "${public_ip}"
    return 0
  fi

  #generic case
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
  sudo sed -i "/^#portal:/c\portal:\n  url: \"http://${public_ip}:8085\"" /opt/graviteeio/apim/rest-api/config/gravitee.yml
  sudo sed -i "/Content-Security-Policy/{s/localhost/${public_ip}/}" /etc/nginx/conf.d/graviteeio-apim-portal-ui.conf

  # During RPM installation the management-api is started with default value.
  # This mean that the portal is set in mongo DB with value 'http://localhost:4100'
  # Then we have to update the configuration via management-api to update DB as the config in gravitee.yml is overwrite by DB config.
  curl 'http://localhost:8083/management/organizations/DEFAULT/environments/DEFAULT/settings' \
    -u 'admin:admin' \
    --max-time 3 \
    -H 'Content-Type: application/json' \
    -X POST \
    --data-raw "{\"portal\":{\"url\":\"http://${public_ip}:8085/\"}}"
}

install_graviteeio_from_repository(){
  local specific_version="${1}"
  if [[ -n "${specific_version}" ]]; then specific_version="-${specific_version}-1"; fi

  install_graviteeio_repository

  sudo yum install -y "graviteeio-apim-4x${specific_version}"
  echo "Installation of RPMs done."

  sudo systemctl daemon-reload

  echo "configure frontend"
  local public_ip
  if public_ip="$(get_current_public_ip)"
  then
    echo "Public IP detected: ${public_ip}"
    configure_frontend "${public_ip}"
  else
    echo "Public IP not found, configure with localhost"
    configure_frontend "localhost"
  fi

  sudo systemctl start graviteeio-apim-gateway graviteeio-apim-rest-api
  sleep 30
  wait_backends_ready
  open_apim_ports
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

  wait_backends_ready

  echo "configure frontend"
  local public_ip
  if public_ip="$(get_current_public_ip)"
  then
    echo "Public IP detected: ${public_ip}"
    configure_frontend "${public_ip}"
  else
    echo "Public IP not found, configure with localhost"
    configure_frontend "localhost"
  fi

  open_apim_ports

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
    install_openjdk 21
    install_nginx
    install_mongo
    install_elasticsearch
}

wait_backends_ready(){
  local max_iter="${1:-40}"
  local expected_version="${2:-}"

  while ! test_graviteeio_backends "${expected_version}"
  do
    echo "Waiting 3 sec more to let backend startup... ${max_iter}"
    sleep 3
    max_iter=$(( ${max_iter} -1 ))
    if [[ ${max_iter} -lt 1 ]]
    then
      break
    fi
  done

  if test_graviteeio_backends "${expected_version}"
  then
    echo "Management API and Gateway are ready !"
  else
    echo "Management API and/or Gateway are in trouble..." >&2
    return 1
  fi
}

test_graviteeio_backends(){
  local expected_version="${1:-}"
  if [[ -z "${expected_version}" ]]
  then
    expected_version="$(ls -1 /opt/graviteeio/apim/graviteeio-apim-rest-api*/lib/gravitee-apim-rest-api-*.jar | sed 's/^.*\/gravitee-apim-rest-api-.*-\([0-9.]*\)\.jar/\1/' | sort -u | tail -n 1)"
    echo "test_graviteeio on computed expected_version: ${expected_version}"
  fi

  echo "Test from gravitee logs"
  if ls -1 /opt/graviteeio/apim/graviteeio-apim-rest-api*/logs/gravitee.log 2> /dev/null \
    && sed -n '/Gravitee.io - Rest APIs id\[/h; ${x;p}' /opt/graviteeio/apim/graviteeio-apim-rest-api*/logs/gravitee.log | grep -q "version\[${expected_version}\]"
  then
    echo "Management API started successfully"
  else
      echo "ERROR on management api start" >&2
      return 1
  fi

  if ls -1 /opt/graviteeio/apim/graviteeio-apim-gateway*/logs/gravitee.log 2> /dev/null \
    && sed -n '/Gravitee.io - API Gateway id\[/h; ${x;p}' /opt/graviteeio/apim/graviteeio-apim-gateway*/logs/gravitee.log | grep -q "version\[${expected_version}\]"
  then
    echo "Gateway started successfully"
  else
    echo "ERROR on gateway start" >&2
    return 1
  fi
}

test_graviteeio(){
  local expected_version="${1:-}"
  if ! test_graviteeio_backends "${expected_version}"
  then
    return 1
  fi

  echo "Test backend gateway"
  curl --user "admin:adminadmin" "http://localhost:18082/_node"
  echo ""

  echo "Test backend rest-api"
  curl --user 'admin:admin' "http://localhost:8083/management/organizations/DEFAULT/environments/DEFAULT/"
  echo ""

  echo "Test Console UI"
  curl -s 'http://localhost:8084/build.json'
  echo ""

  echo "Test Portal UI"
  curl -s 'http://localhost:8085/' | grep '<app-root></app-root>'
  echo ""
}

test_graviteeio_upgrade(){
  local first_version second_version
  first_version="${1:-4.4.9}"
  second_version="${2:-4.5.0}"

  echo "Install APIM from ${first_version}"
  if [[ -d "${first_version}" ]]
  then
    install_graviteeio_from_local_rpms "${first_version}"
  else
    install_graviteeio_from_repository "${first_version}"
  fi
  sleep 1
  add_user
  sudo systemctl restart graviteeio-apim-rest-api
  sleep 20
  wait_backends_ready
  sleep 3
  echo "Test backend rest-api with gravitee user"
  curl --user 'gravitee:bloubiboulga' "http://localhost:8083/management/organizations/DEFAULT/environments/DEFAULT/"
  echo "OK."
  create_gravitee_echo_api
  sleep 1
  if [[ -d "${first_version}" ]]
  then
    test_graviteeio
  else
    test_graviteeio "${first_version}"
  fi

  echo "APIM ${first_version} installed - use it"
  call_echo_api_x_times
  echo "Wait a bit to let management api load analytics"
  sleep 10
  call_apim_dashboard
  call_echo_api_analytics

  echo "Upgrade APIM to ${second_version}"
  if [[ -d "${second_version}" ]]
  then
    sudo yum upgrade -y "${second_version}"/*.rpm
  else
    sudo yum upgrade -y "graviteeio-apim-4x-${second_version}-1"
  fi
  sudo systemctl daemon-reload
  sleep 1
  sudo systemctl restart graviteeio-apim-gateway graviteeio-apim-rest-api
  sleep 45
  sudo systemctl restart nginx
  sleep 1
  if [[ -d "${second_version}" ]]
  then
    test_graviteeio
  else
    test_graviteeio "${second_version}"
  fi

  echo "APIM ${second_version} installed - use it"
  call_echo_api_x_times
  echo "Wait a bit to let management api load analytics"
  sleep 10
  call_apim_dashboard
  call_echo_api_analytics


  echo "Test backend rest-api with gravitee user (gravitee.yml config file changes are still here)"
  curl --user 'gravitee:bloubiboulga' "http://localhost:8083/management/organizations/DEFAULT/environments/DEFAULT/"

  echo "Upgrade from ${first_version} to ${second_version} done."
}

call_echo_api_x_times(){
  local gateway_baseurl nb_iteration
  gateway_baseurl="${1:-http://localhost:8082}"
  nb_iteration="${2:-100}"

  for i in $(seq 1 ${nb_iteration})
  do
    curl -s "${gateway_baseurl}/echo" > /dev/null
    echo -n "."
  done
  echo ""
}

call_echo_api_analytics(){
  local management_baseurl api_id
  management_baseurl="${1:-http://localhost:8083/management}"

  api_id="$(curl -s "${management_baseurl}/v2/environments/DEFAULT/apis/_search?page=1&perPage=25" \
    -u 'admin:admin' \
    -H 'Content-Type: application/json' \
    --data-raw '{"query":"name:echo"}' | jq --raw-output '.data[0].id')"

  echo "echo api id: ${api_id}"

  echo "requests-count:"
  curl "${management_baseurl}/v2/environments/DEFAULT/apis/${api_id}/analytics/requests-count" \
    -u 'admin:admin' \
    -H 'Accept: application/json, text/plain, */*'
  echo ""

  echo "average-connection-duration:"
  curl "${management_baseurl}/v2/environments/DEFAULT/apis/${api_id}/analytics/average-connection-duration" \
    -u 'admin:admin' \
    -H 'Accept: application/json, text/plain, */*'
  echo ""

  echo "response-status-ranges:"
  curl "${management_baseurl}/v2/environments/DEFAULT/apis/${api_id}/analytics/response-status-ranges" \
    -u 'admin:admin' \
    -H 'Accept: application/json, text/plain, */*'
  echo ""
}

call_apim_dashboard(){
  local management_baseurl date_from date_to analytics_params
  management_baseurl="${1:-http://localhost:8083/management}"
  date_from="$(date --date="now-15mins" '+%s')"
  date_to="$(date --date="now" '+%s')"

  for analytics_params in "type=count&field=application" "type=group_by&field=api" "type=count&field=api" "type=group_by&field=lifecycle_state" "type=group_by&field=state" "type=group_by&field=status" "type=stats&field=response-time"
  do
    echo "${analytics_params}:"
    curl "${management_baseurl}/organizations/DEFAULT/environments/DEFAULT/analytics?${analytics_params}&interval=2000&from=${date_from}&to=${date_to}" \
        -u 'admin:admin' \
        -H 'Accept: application/json, text/plain, */*'
    echo ""
  done

  echo "events:"
  curl "${management_baseurl}/organizations/DEFAULT/environments/DEFAULT/platform/events?type=START_API,STOP_API,PUBLISH_API,UNPUBLISH_API&query=&api_ids=&from=${date_from}&to=${date_to}&page=0&size=5" \
    -u 'admin:admin' \
    -H 'Accept: application/json, text/plain, */*'
  echo ""
}

create_gravitee_echo_api(){
  local api_id plan_id management_baseurl
  management_baseurl="${1:-http://localhost:8083/management}"

  echo "Create echo api ..."
  api_id="$(curl -s "${management_baseurl}/v2/environments/DEFAULT/apis" \
    -u 'admin:admin' \
    -H 'Content-Type: application/json' \
    --data-raw '{"definitionVersion":"V4","name":"echo","apiVersion":"1.0.0","description":"The famous Gravitee echo api","listeners":[{"type":"HTTP","paths":[{"path":"/echo"}],"entrypoints":[{"type":"http-proxy","configuration":{},"qos":"AUTO"}]}],"type":"PROXY","endpointGroups":[{"name":"Default HTTP proxy group","type":"http-proxy","sharedConfiguration":{"http":{"version":"HTTP_1_1","keepAlive":true,"keepAliveTimeout":30000,"connectTimeout":3000,"pipelining":false,"readTimeout":10000,"useCompression":true,"idleTimeout":60000,"followRedirects":false,"maxConcurrentConnections":20},"proxy":{"enabled":false,"useSystemProxy":false},"ssl":{"hostnameVerifier":true,"trustAll":false,"trustStore":{"type":""},"keyStore":{"type":""}}},"endpoints":[{"name":"Default HTTP proxy","type":"http-proxy","weight":1,"inheritConfiguration":true,"configuration":{"target":"https://api.gravitee.io/echo"}}]}]}' \
    | jq --raw-output '.id')"

  sleep 0.2

  echo "Create plan for api: ${api_id}"
  plan_id="$(curl -s "${management_baseurl}/v2/environments/DEFAULT/apis/${api_id}/plans" \
    -u 'admin:admin' \
    -H 'Content-Type: application/json' \
    --data-raw '{"definitionVersion":"V4","name":"Default Keyless (UNSECURED)","description":"Default unsecured plan","mode":"STANDARD","security":{"type":"KEY_LESS","configuration":{}},"validation":"MANUAL"}' \
    | jq --raw-output '.id')"

  sleep 0.2

  echo "Publish api (${api_id}) with plan (${plan_id})"
  curl "${management_baseurl}/v2/environments/DEFAULT/apis/${api_id}/plans/${plan_id}/_publish" \
    -u 'admin:admin' \
    -H 'Content-Type: application/json' \
    --data-raw '{}'

  sleep 0.2

  echo "Start api (${api_id})"
  curl "${management_baseurl}/v2/environments/DEFAULT/apis/${api_id}/_start" \
    -u 'admin:admin' \
    -H 'Content-Type: application/json' \
    --data-raw '{}'
}

add_user(){
  local username bcrypt_password restart
  username="${1:-gravitee}"
  # default password: bloubiboulga
  # to generate new password: htpasswd -bnBC 10 "" bloubiboulga | tr -d ':\n' | sed 's/^$2y\$/$2a$/'
  bcrypt_password="${2:-\$2a\$10\$iJmJIgf7\/Y14AtR\/lKkyzeX5cyL5nL4lgePjiBVvRkq4m652E70oy}"
  restart="${3:-false}"
  sudo sed -i "/^security:/,/^ *# Enable authentication/{
    /username: application1/,/#email:/{
      s/#email:/#email:\n        - user:\n          username: ${username}\n          #firstname:\n          #lastname:\n          password: ${bcrypt_password}\n          roles: ORGANIZATION:ADMIN,ENVIRONMENT:ADMIN\n          #email:/
    }
  }" /opt/graviteeio/apim/rest-api/config/gravitee.yml

  if [[ "${restart}" == "true" ]]
  then
    sudo systemctl restart graviteeio-apim-rest-api
    wait_backends_ready
  fi

  echo "User ${username} added."
}

uninstall(){
  sudo yum remove -y graviteeio-apim-*

  if [[ "${1:-}" == "--hard" && -d /opt/graviteeio ]]
  then
    echo "Delete folder /opt/graviteeio"
    sudo rm -rf /opt/graviteeio
  fi
}

help(){
  cat <<EOF
This script let you install GraviteeIO from local RPM or official published repo

usage : $0 [COMMAND]

COMMAND : (default: install_prerequities)
${COMMANDS}

exemple :
./install_redhat.sh install_prerequities

./install_redhat.sh install_graviteeio_from_repository
./install_redhat.sh install_graviteeio_from_repository 4.2.6

./install_redhat.sh install_graviteeio_from_local_rpms
./install_redhat.sh install_graviteeio_from_local_rpms /path/to/rpms/folder

./install_redhat.sh test_graviteeio

./install_redhat.sh create_gravitee_echo_api
curl -s -H "say: gloubiboulga" "http://localhost:8082/echo" | jq '.'

./install_redhat.sh test_graviteeio_upgrade
./install_redhat.sh test_graviteeio_upgrade "4.4.9" "4.5.0"
./install_redhat.sh test_graviteeio_upgrade "4.4.9" "/home/azureadmin/rpms"

./install_redhat.sh uninstall

EOF
}

### Default context ###
COMMANDS="$(sed -n '/^[a-z].*(){$/ s/(){//p' $0)"
COMMAND="install_prerequities"

### Parse args ###
if [[ -n "${1:-}" ]]
then
  COMMAND="$1"
  shift
fi

### main ###
${COMMAND} $@
