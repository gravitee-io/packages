# Gravitee.io - Packages (RPM)

Repository containing the tooling and scripts to build and publish RPM packages of Gravitee.io to [PackageCloud](https://packagecloud.io/graviteeio/rpms).

## How to build and test RPMs locally?

_Here is an example to build and test APIM RPMs locally:_

### Build the RPMs

Build the RPMs using `build.sh`:

```shell
cd apim/4.x
./build.sh -v [YOUR_VERSION]
```

### Run CentOS docker image

Run CentOS docker container with a volume mount:
```shell
export PATH_TO_LOCAL_RPMS=$(pwd)
docker run --rm -v "${PATH_TO_LOCAL_RPMS}:/local-rpms" -w "/local-rpms" -it --entrypoint bash centos:7
```

### Determine the tag to use

For a final release, the TAG of your RPM package should look like:
```shell
TAG=[YOUR_VERSION]-1
...
# example for a 4.0.0 version
TAG= 4.0.0-1
```

For a pre-release (aka alpha version), the TAG of your RPM package should look like:
```shell
TAG=[YOUR_VERSION]-0.x.alpha
...
# example for a 4.0.0-alpha.2 version
TAG= 4.0.0-0.2.alpha
```
### Install local RPMs

Inside the container:
```shell
yum install /local-rpms/graviteeio-apim-gateway-4x-[TAG].noarch.rpm
yum install /local-rpms/graviteeio-apim-management-ui-4x-[TAG].noarch.rpm
yum install /local-rpms/graviteeio-apim-portal-ui-4x-[TAG].noarch.rpm
yum install /local-rpms/graviteeio-apim-rest-api-4x-[TAG].noarch.rpm
```


### How to install RPMs from PackageCloud?

Inside the container:
```shell
# Add packagecloud registry to be able to run install APIM
echo "[graviteeio]
name=graviteeio
baseurl=https://packagecloud.io/graviteeio/rpms/el/7/\$basearch
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/graviteeio/rpms/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300" > /etc/yum.repos.d/graviteeio.repo

# For *-ui-* package, nginx is required, to install it:
yum install -y epel-release
yum install -y nginx

# Some dark magic to have everything related to repo working properly on my local docker container
cd /etc/yum.repos.d/
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
yum install pygpgme yum-utils
yum update -y
yum -q makecache -y --disablerepo='*' --enablerepo='graviteeio'

# Install RPMs
yum install graviteeio-apim-4x-[TAG].noarch -y
```

## Manual Integration test

### Process to test an APIM upgrade

1. provision a VM with Redhat RHEL 8.5 or 9

2. On your laptop, build rpm locally for 2 versions:
```bash
cd apim/3.x
mkdir -p rpms/3.20.{9,21}

[ -d .staging ] && rm -rf .staging
./build.sh -v 3.20.9
rm -f graviteeio-apim-3x-*.rpm   # as we install each rpm manually, we do not use the global rpm.
mv graviteeio-apim-*.rpm rpms/3.20.9/

[ -d .staging ] && rm -rf .staging
./build.sh -v 3.20.21
rm -f graviteeio-apim-3x-*.rpm   # as we install each rpm manually, we do not use the global rpm.
mv graviteeio-apim-*.rpm rpms/3.20.21/
```

3. Connect via ssh to your VM and enable port forwarding to be able to test connexion on APIM
```bash
ssh -i key.pem \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -L localhost:8082:localhost:8082 \
    -L localhost:8083:localhost:8083 \
    -L localhost:8084:localhost:8084 \
    -L localhost:8085:localhost:8085 \
    gravitee@192.168.0.253
```

4. install all prerequities without gravitee (to not install the latest version)
```bash
curl -L https://raw.githubusercontent.com/gravitee-io/scripts/master/apim/3.x/redhat/install_redhat.sh | sed '/main()/,/}/{/install_graviteeio/d}' | bash
```

5. copy the rpms folder into your VM (from your laptop)
```bash
scp -r -i key.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no rpms gravitee@192.168.0.253:.
```
Note: we use here our own private key `key.pem`, do not add this ssh info on our local config, use our user `gravitee` on the VM with IP `192.168.0.253`.

6. into the VM install the first rpms and then start services
```bash
cd ~/rpms/3.20.9
for rpm in graviteeio-apim-*.rpm; do sudo yum install -y "${rpm}"; done
sudo systemctl start nginx.service graviteeio-apim-rest-api.service graviteeio-apim-gateway.service
```

7. in another terminal, you can check which version of APIM is answering (Note you can install and use `tmux`):
```bash
while true; do echo "$(date)    $(curl -s -u 'admin:adminadmin' 'http://localhost:18083/_node' | jq -r '.version.MAJOR_VERSION')"; sleep 1; done
```

8. update rest-api config file to add another admin user and restart service to use it:
```bash
sed -i '/^security:/,/^ *# Enable authentication/{/username: application1/,/#email:/{s/#email:/#email:\n        - user:\n          username: gravitee\n          #firstname:\n          #lastname:\n          # Password value: bloubiboulga\n          password: $2a$10$iJmJIgf7\/Y14AtR\/lKkyzeX5cyL5nL4lgePjiBVvRkq4m652E70oy\n          roles: ORGANIZATION:ADMIN,ENVIRONMENT:ADMIN\n          #email:/}}' /opt/graviteeio/apim/rest-api/config/gravitee.yml

sudo systemctl restart graviteeio-apim-rest-api.service
```
Note: the command used to generate the password is: `htpasswd -bnBC 10 "" bloubiboulga | tr -d ':\n' | sed 's/^$2y\$/$2a$/'`

9. Connect into APIM on http://localhost:8084 with new created user/pass: `gravitee/bloubiboulga`

10. Now in the VM, we want to upgrade to 3.20.21 without loosing configuration
```bash
cd ~/rpms/3.20.21
for rpm in graviteeio-apim-*.rpm; do sudo yum upgrade -y "${rpm}"; done
sudo systemctl start nginx.service graviteeio-apim-rest-api.service graviteeio-apim-gateway.service
```

11. We should be able to connect on http://localhost:8084 always with user `gravitee`. The curl command to show the version should answer `3.20.21`


### Test only that config and plugins are kept during an APIM upgrade

This test run on docker only to ensure that upgrade will keep change in `gravitee.yml` and that custom plugin are kept also.


1. Build rpm locally for 2 versions:
```bash
cd apim/4.x
mkdir -p rpms/{4.0.12,4.1.3}

[ -d .staging ] && rm -rf .staging
./build.sh -v 4.0.12
rm -f graviteeio-apim-4x-*.rpm   # as we install each rpm manually, we do not use the global rpm.
mv graviteeio-apim-*.rpm rpms/4.0.12/

[ -d .staging ] && rm -rf .staging
./build.sh -v 4.1.3
rm -f graviteeio-apim-4x-*.rpm   # as we install each rpm manually, we do not use the global rpm.
mv graviteeio-apim-*.rpm rpms/4.1.3/
```

2. Run a local docker container with a volume for RPMs:
```bash
docker run --rm -v "${PWD}/rpms:/local-rpms" -w "/local-rpms" -it --entrypoint bash centos:7
```

3. Install first version of rest-api:
```bash
yum install -y 4.0.12/graviteeio-apim-rest-api-4x-4.0.12-1.noarch.rpm
```

4. Update configuration file and create a fake new plugin and then, list all existing plugins
```bash
sed -i '/^security:/,/^ *# Enable authentication/{/username: application1/,/#email:/{s/#email:/#email:\n        - user:\n          username: gravitee\n          #firstname:\n          #lastname:\n          # Password value: bloubiboulga\n          password: $2a$10$iJmJIgf7\/Y14AtR\/lKkyzeX5cyL5nL4lgePjiBVvRkq4m652E70oy\n          roles: ORGANIZATION:ADMIN,ENVIRONMENT:ADMIN\n          #email:/}}' /opt/graviteeio/apim/rest-api/config/gravitee.yml

cp /opt/graviteeio/apim/graviteeio-apim-rest-api/plugins/{gravitee-alert-engine-connectors-ws-2.1.0.zip,gravitee-zzz-custom-fake-plugin-0.0.1.zip}

ls -1 /opt/graviteeio/apim/graviteeio-apim-rest-api/plugins/ > /tmp/plugin-list_4.0.12.txt
```

5. Proceed to the upgrade and update plugin list files
```bash
yum upgrade -y 4.1.3/graviteeio-apim-rest-api-4x-4.1.3-1.noarch.rpm

ls -1 /opt/graviteeio/apim/graviteeio-apim-rest-api/plugins/ > /tmp/plugin-list_4.1.3.txt
```

6. Validate that changes have been kept in config file and manually install plugin has not been deleted:
```bash
if grep -q "bloubiboulga" /opt/graviteeio/apim/rest-api/config/gravitee.yml; then echo "config file ✔"; else echo "config file ✕"; fi

if [[ -f "/opt/graviteeio/apim/graviteeio-apim-rest-api/plugins/gravitee-zzz-custom-fake-plugin-0.0.1.zip" ]]; then echo "plugin ✔"; else echo "plugin ✕"; fi
```

7. Validate plugin list manually:
```bash
diff -y /tmp/plugin-list_4.0.12.txt /tmp/plugin-list_4.1.3.txt
```
