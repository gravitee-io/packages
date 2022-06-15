# Gravitee.io - Packages (RPM)

Repository containing the tooling and scripts to build and publish RPM packages of Gravitee.io to [PackageCloud](https://packagecloud.io/graviteeio/rpms).

## How to build and test RPMs locally?

_Here is an example to build and test APIM RPMs locally:_

### Build the RPMs

Build the RPMs using `build.sh`:

```shell
cd apim/3.x
./build.sh -v [YOUR_VERSION]
```

### Run CentOS docket image

Run CentOS docker container with a volume mount:
```shell
export PATH_TO_LOCAL_RPMS=$(pwd)
docker run --rm -v ${PATH_TO_LOCAL_RPMS}:/local-rpms -it --entrypoint bash centos
```

### Install local RPMs

Inside the container:
```shell
yum install /local-rpms/graviteeio-apim-gateway-3x-[YOUR_VERSION]-0.noarch.rpm
yum install /local-rpms/graviteeio-apim-management-ui-3x-[YOUR_VERSION]-0.noarch.rpm
yum install /local-rpms/graviteeio-apim-portal-ui-3x-[YOUR_VERSION]-0.noarch.rpm
yum install /local-rpms/graviteeio-apim-rest-api-3x-[YOUR_VERSION]-0.noarch.rpm
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

# Some dark magic to have everything related to repo working properly on my local docker container
cd /etc/yum.repos.d/
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
yum install pygpgme yum-utils
yum update -y
yum -q makecache -y --disablerepo='*' --enablerepo='graviteeio'

# Install RPMs
yum install graviteeio-apim-3x-[YOUR_VERSION]-0.noarch -y
```
