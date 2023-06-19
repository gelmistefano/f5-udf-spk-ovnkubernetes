# F5 UDF OCP Cluster w/ ovnKubernetes CNI

This guide allow to install on UDF a complete OCP Cluster.
_Tested in 4.11.9_

## Installation on UDF

This steps allows to create a new deployment on UDF from scratch

### Environment

Create a new Deployment using the UDF hypervisor

| Network Name | Subnet      |
| ------------ | ----------- |
| Management   | 10.1.1.0/24 |
| External     | 10.1.1.0/24 |

Create the following VMs (in order):

| VM UDF Name     | Template     | vCPU   | Memory   | Disk Space | Mgmt Address | External Address |
| --------------- | ------------ | ------ | -------- | ---------- | ------------ | ---------------- |
| ocp-provisioner | Ubuntu 20.04 | 4 vCPU | 8GB RAM  | 150GB vHD  | 10.1.1.4     | 10.1.1.4         |
| ocp-bootstrap   | RHEL 8.3     | 4 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.5     | 10.1.1.5         |
| ocp-master-1    | RHEL 8.3     | 8 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.6     | 10.1.1.6         |
| ocp-master-2    | RHEL 8.3     | 8 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.7     | 10.1.1.7         |
| ocp-master-3    | RHEL 8.3     | 8 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.8     | 10.1.1.8         |
| ocp-worker-1    | RHEL 8.3     | 8 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.9     | 10.1.1.9         |
| ocp-worker-2    | RHEL 8.3     | 8 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.10    | 10.1.1.10        |
| ocp-worker-3    | RHEL 8.3     | 8 vCPU | 16GB RAM | 100GB vHD  | 10.1.1.11    | 10.1.1.11        |
| jumphost        | Windows 10   | 4 vCPU | 8GB RAM  | 90GB vHD   | 10.1.1.12    | 10.1.10.12       |

### Configuration: ocp-provisioner

SSH into the provisioner and become super-user and set hostname

```bash
sudo bash
hostnamectl set-hostname ocp-provisioner
sed -i '1s/$/ ocp-provisioner/' /etc/hosts
```

Install packages and addon

```bash
apt update && \
apt install -y vim ipmitool tmux tar bind9-utils dnsmasq nginx telnet wget tcpdump git iptables unzip dnsmasq jq net-tools ca-certificates apache2-utils make moreutils nfs-kernel-server ca-certificates curl gnupg
```

Clone this repo into your home directory and jump into it:

```bash
cd f5-udf-spk-ovnkubernetes
```

Create new `/etc/hosts` from file `hosts`:

```bash
cp -f ocp-deploy/hosts /etc/hosts
```

Modify the DNS resolver config:

```bash
systemctl stop systemd-resolved
systemctl disable systemd-resolved

rm -rf /etc/resolv.conf

cat <<EOF > /etc/resolv.conf
nameserver 10.1.1.4
nameserver 8.8.8.8
search f5-udf.com
EOF
```

Enable `ens6` interface:

```bash
sed -i '$ a\        ens6:\n            dhcp4: true' /etc/netplan/50-cloud-init.yaml
netplan apply
```

Enable dnsmasq:

```bash
echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf
echo "address=/apps.ocp.f5-udf.com/10.1.1.4" > /etc/dnsmasq.d/apps-wildcard.conf
echo "address=/am.ocp.f5-udf.com/10.1.1.50" > /etc/dnsmasq.d/am-wildcard.conf
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl enable dnsmasq
systemctl restart dnsmasq
```

### Downlaod bootstrap files for Openshift

Download the required files:

```bash
mkdir /usr/share/nginx/html/installations
cd /usr/share/nginx/html/installations
export OCP_RELEASE="4.11.9"
export RHCOS_VERSION="4.11"
export RHCOS_RELEASE="$RHCOS_VERSION"."9"

wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_RELEASE/openshift-install-linux-$OCP_RELEASE.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_RELEASE/openshift-client-linux-$OCP_RELEASE.tar.gz

tar xvf /usr/share/nginx/html/installations/openshift-client-linux-$OCP_RELEASE.tar.gz
tar xvf /usr/share/nginx/html/installations/openshift-install-linux-$OCP_RELEASE.tar.gz

wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$RHCOS_VERSION"/$RHCOS_RELEASE"/rhcos-live-kernel-x86_64
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$RHCOS_VERSION"/$RHCOS_RELEASE"/rhcos-live-initramfs.x86_64.img
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$RHCOS_VERSION"/$RHCOS_RELEASE"/rhcos-live-rootfs.x86_64.img
```

You need to register yourself on the Red Hat Cloud portal and retrieve your pullSecret from

- [user-provisioned-infrastructure](https://cloud.redhat.com/openshift/install/metal/user-provisioned)
- Selecy "Copy pull secret" or "Donwload pull secret"

Assign the following variables

```bash
USER=ubuntu
REPO=f5-udf-spk-ovnkubernetes/ocp-deploy
SSHKEY=$(cat /home/$USER/.ssh/authorized_keys | grep access-method-key)
OCPSECRET='<put secret from https://console.redhat.com/openshift/install/metal/user-provisioned>'
```

### Openshift install-config.yaml (main config file)

We are now going to create the Openshift Installation and Configuration Files.

Copy the sample install-config.yaml from the config-files directory into the following folder:

```bash
cd /usr/share/nginx/html/installations/
cp /home/$USER/$REPO/install-config.yml install-config.yaml
sed -i "s@sshKey: ''@sshKey: '$SSHKEY'@g" install-config.yaml
sed -i "s/pullSecret: ''/pullSecret: '$OCPSECRET'/g" install-config.yaml
cp install-config.yaml install-config.yaml.back
rm -rf metadata.json bootstrap*.ign master*.ign worker*.ign auth openshift manifests .openshift_install_state.json .openshift_install.log bootstrap master-{1,2,3} worker-{1,2,3} check-ignite.sh custom-ignite transpile
```

Create the Openshift manifest config files:

```bash
/usr/share/nginx/html/installations/openshift-install create manifests --dir=/usr/share/nginx/html/installations/
/usr/share/nginx/html/installations/openshift-install create ignition-configs --dir=/usr/share/nginx/html/installations/
```

Make sure all files are readable by the nginx web server

```bash
chmod -R o+r /usr/share/nginx/html/
```

Customize bashrc

```bash
echo 'export KUBECONFIG=/usr/share/nginx/html/installations/auth/kubeconfig' >> /home/$USER/.bashrc
echo 'PATH=$PATH:/usr/local/bin:/usr/share/nginx/html/installations' >> /home/$USER/.bashrc

chown -R $USER:www-data /usr/share/nginx/html/installations/
find /usr/share/nginx/html/installations/ -exec chmod o-rwx {} \;
chmod g-rwx /usr/share/nginx/html/installations/auth/kubeconfig
. /home/$USER/.bashrc


oc completion bash > oc_bash_completion
cp oc_bash_completion /etc/bash_completion.d/

. /home/$USER/.bashrc
```

## General Build considerations

- Create an SSH Access with the user "core" for all the OCP nodes
- The kubeadmin (temporary admin) password is in the file cat /usr/share/nginx/html/installations/auth/kubeadmin-password

## ocp-bootstrap Build

From **ocp-provisioner**, reconfigure nginx to load balance requests to the bootstrap node:

```bash
cp /home/$USER/$REPO/nginx-conf/nginx.conf-* /etc/nginx/
cd /etc/nginx
rm -f nginx.conf
ln -s nginx.conf-initial nginx.conf
systemctl restart nginx
systemctl status nginx
systemctl enable nginx
```

Connect to **ocp-bootstrap** host via ssh and download and setup RHCOS kernel and initramfs files:

```bash
sudo bash
echo "nameserver 10.1.1.4" > /etc/resolv.conf
curl -O -L -J http://ocp-provisioner:8080/installations/rhcos-live-kernel-x86_64
curl -O -L -J http://ocp-provisioner:8080/installations/rhcos-live-initramfs.x86_64.img
mv rhcos-live-kernel-x86_64 /boot/vmlinuz-rhcos
mv rhcos-live-initramfs.x86_64.img /boot/initramfs-rhcos.img
```

Now install a new grub line to boot the new RHCOS kernel, enabling the netowrk and pointing to the NGINX Web Server running on ocp-bootstrap to download install file:
_NB: When using RHEL 8 images somehow the VM changes the interface names from eno5 to enp0s4.._

```bash
IFACE=enp0s4
grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.5::10.1.1.1:255.255.255.0:ocp-bootstrap.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/bootstrap.ign coreos.inst.copy_network" --initrd=/boot/initramfs-rhcos.img --make-default --title=rhcos
```

And reboot the host.

From **ocp-provisioner**, run the following commands:

```bash
cd /usr/share/nginx/html/installations
./openshift-install --dir=. wait-for bootstrap-complete --log-level debug
```

Watch for indication that API is UP.

```bash
root@ubuntu:/usr/share/nginx/html/installations# ./openshift-install --dir=. wait-for bootstrap-complete --log-level debug
DEBUG OpenShift Installer 4.11.9
DEBUG Built from commit 01a6869a6f1208fb4d112060c5971432fdd619cf
INFO Waiting up to 20m0s (until 11:25AM) for the Kubernetes API at https://api.ocp.f5-udf.com:6443...
DEBUG Still waiting for the Kubernetes API: Get "https://api.ocp.f5-udf.com:6443/version": net/http: TLS handshake timeout
DEBUG Still waiting for the Kubernetes API: Get "https://api.ocp.f5-udf.com:6443/version": EOF
DEBUG Still waiting for the Kubernetes API: Get "https://api.ocp.f5-udf.com:6443/version": net/http: TLS handshake timeout
DEBUG Still waiting for the Kubernetes API: Get "https://api.ocp.f5-udf.com:6443/version": EOF
DEBUG Still waiting for the Kubernetes API: Get "https://api.ocp.f5-udf.com:6443/version": read tcp 10.1.1.4:39032->10.1.1.4:6443: read: connection reset by peer
DEBUG Still waiting for the Kubernetes API: Get "https://api.ocp.f5-udf.com:6443/version": EOF
INFO API v1.24.0+dc5a2fd up
DEBUG Loading Install Config...
DEBUG   Loading SSH Key...
DEBUG   Loading Base Domain...
DEBUG     Loading Platform...
DEBUG   Loading Cluster Name...
DEBUG     Loading Base Domain...
DEBUG     Loading Platform...
DEBUG   Loading Networking...
DEBUG     Loading Platform...
DEBUG   Loading Pull Secret...
DEBUG   Loading Platform...
DEBUG Using Install Config loaded from state file
INFO Waiting up to 30m0s (until 11:39AM) for bootstrapping to complete...
```

**_NB: After the API is UP continue with masters node build, don't wait for bootstrap complete message._**

## Master Build

Connect on each **master** host via ssh, set the following variable and donwload adn setup RHCOS kernel and initramfs files:

```bash
IFACE=enp0s4
curl -O -L -J http://10.1.1.4:8080/installations/rhcos-live-kernel-x86_64
curl -O -L -J http://10.1.1.4:8080/installations/rhcos-live-initramfs.x86_64.img
sudo mv rhcos-live-kernel-x86_64 /boot/vmlinuz-rhcos
sudo mv rhcos-live-initramfs.x86_64.img /boot/initramfs-rhcos.img
```

Now install a new grub line to boot the new RHCOS kernel, enabling the netowrk and pointin to the NGINX Web Server running on ocp-bootstrap to download install file:

### master-1

```bash
sudo grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.6::10.1.1.1:255.255.255.0:master-1.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/master.ign" --make-default --title=rhcos
sudo reboot
```

### master-2

```bash
sudo grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.7::10.1.1.1:255.255.255.0:master-2.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/master.ign" --make-default --title=rhcos
sudo reboot
```

### master-3

```bash
sudo grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.8::10.1.1.1:255.255.255.0:master-3.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/master.ign" --make-default --title=rhcos
sudo reboot
```

Open the **master** console from UDF and watch the process while rebooting the box (it will take some time).

Wait until bootstrap is complete in ocp-provioner

```bash
DEBUG Bootstrap status: complete
INFO It is now safe to remove the bootstrap resources
DEBUG Time elapsed per stage:
DEBUG Bootstrap Complete: 13m59s
DEBUG API: 3m58s
INFO Time elapsed: 13m59s
```

## Worker Build

Set the final nginx configuration in **ocp-provider**:

```bash
cd /etc/nginx
sudo rm -f nginx.conf
sudo ln -s nginx.conf-final nginx.conf
sudo nginx -s reload
```

At this point it is possible to use kubectl

Connect on each **worker** hosts via ssh, set the following variable and donwload/setup the following RHCOS kernel and initramfs files:

```bash
IFACE=enp0s4
curl -O -L -J http://10.1.1.4:8080/installations/rhcos-live-kernel-x86_64
curl -O -L -J http://10.1.1.4:8080/installations/rhcos-live-initramfs.x86_64.img
sudo mv rhcos-live-kernel-x86_64 /boot/vmlinuz-rhcos
sudo mv rhcos-live-initramfs.x86_64.img /boot/initramfs-rhcos.img
```

Now install a new grub line to boot the new RHCOS kernel, enabling the netowrk and pointin to the NGINX Web Server running on ocp-bootstrap to download install file:

### worker-1

```bash
sudo grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.9::10.1.1.1:255.255.255.0:worker-1.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/worker.ign" --make-default --title=rhcos
sudo reboot
```

### worker-2

```bash
sudo grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.10::10.1.1.1:255.255.255.0:worker-2.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/worker.ign" --make-default --title=rhcos
sudo reboot
```

### worker-3

```bash
sudo grubby --add-kernel=/boot/vmlinuz-rhcos --args="ip=10.1.1.11::10.1.1.1:255.255.255.0:worker-3.ocp.f5-udf.com:$IFACE:none nameserver=10.1.1.4 rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.live.rootfs_url=http://10.1.1.4:8080/installations/rhcos-live-rootfs.x86_64.img coreos.inst.ignition_url=http://10.1.1.4:8080/installations/worker.ign" --make-default --title=rhcos
sudo reboot
```

Open the **worker** console from UDF and watch the process while rebooting the box (it will take some time).

## Setup more appropiate permisisons for the installations folder

**_WAIT UNTIL THE WORKER NODES ARE UP BEFORE PROCEED_**

At this point you should see the next

```bash
ubuntu@ocp-provisioner:~$ oc get nodes
NAME                      STATUS   ROLES    AGE   VERSION
master-1.ocp.f5-udf.com   Ready    master   31m   v1.24.0+dc5a2fd
master-2.ocp.f5-udf.com   Ready    master   30m   v1.24.0+dc5a2fd
master-3.ocp.f5-udf.com   Ready    master   27m   v1.24.0+dc5a2fd
```

This means that the workers are not yet accepted, run the following command in a new terminal until you find they are added to the cluster

```bash
while date ; do
oc get csr --no-headers | grep Pending | awk '{print $1}' | xargs --no-run-if-empty oc adm certificate approve
sleep 5
done
```

You should see CSR approved, wait until all csr will be approved (based on node's number):

```bash
Fri May 19 15:47:51 UTC 2023
certificatesigningrequest.certificates.k8s.io/csr-bbrgk approved
certificatesigningrequest.certificates.k8s.io/csr-c92vc approved
certificatesigningrequest.certificates.k8s.io/csr-nmdx7 approved
Fri May 19 15:47:56 UTC 2023
Fri May 19 15:48:02 UTC 2023
certificatesigningrequest.certificates.k8s.io/csr-4b5n7 approved
certificatesigningrequest.certificates.k8s.io/csr-ghbcf approved
certificatesigningrequest.certificates.k8s.io/csr-nzrtl approved
Fri May 19 15:48:07 UTC 2023
Fri May 19 15:48:12 UTC 2023
Fri May 19 15:48:17 UTC 2023
Fri May 19 15:48:22 UTC 2023
```

Use the following command to see that all nodes are ready:

```bash
watch oc get nodes
```

Use the following commands to see that cluster operators are Active

```bash
watch oc get co
```

Wait until all components are available and not degraded:

```bash
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.11.9    True        False         False      2m32s
baremetal                                  4.11.9    True        False         False      41m
cloud-controller-manager                   4.11.9    True        False         False      47m
cloud-credential                           4.11.9    True        False         False      69m
cluster-autoscaler                         4.11.9    True        False         False      41m
config-operator                            4.11.9    True        False         False      42m
console                                    4.11.9    True        False         False      4m23s
csi-snapshot-controller                    4.11.9    True        False         False      41m
dns                                        4.11.9    True        False         False      41m
etcd                                       4.11.9    True        False         False      40m
image-registry                             4.11.9    True        False         False      35m
ingress                                    4.11.9    True        False         False      14m
insights                                   4.11.9    True        False         False      29m
kube-apiserver                             4.11.9    True        False         False      32m
kube-controller-manager                    4.11.9    True        False         False      39m
kube-scheduler                             4.11.9    True        False         False      38m
kube-storage-version-migrator              4.11.9    True        False         False      41m
machine-api                                4.11.9    True        False         False      41m
machine-approver                           4.11.9    True        False         False      41m
machine-config                             4.11.9    True        False         False      35m
marketplace                                4.11.9    True        False         False      40m
monitoring                                 4.11.9    True        False         False      6m41s
network                                    4.11.9    True        False         False      41m
node-tuning                                4.11.9    True        False         False      40m
openshift-apiserver                        4.11.9    True        False         False      34m
openshift-controller-manager               4.11.9    True        False         False      38m
openshift-samples                          4.11.9    True        False         False      35m
operator-lifecycle-manager                 4.11.9    True        False         False      41m
operator-lifecycle-manager-catalog         4.11.9    True        False         False      41m
operator-lifecycle-manager-packageserver   4.11.9    True        False         False      35m
service-ca                                 4.11.9    True        False         False      42m
storage                                    4.11.9    True        False         False      42m
```

_NB: To receive more information, you can use the command `oc get events -A -w`_

### Bugs found

DNS operator fails. This should be first one to fix because other operators depend on it.

If you find that the dns cluster operator doesn't become available, check if that's because another service has picked dns' hardcoded address .10 by checking the dns operator logs:

```bash
oc -n openshift-dns-operator logs dns-operator-<id> dns-operator --tail=100 -f

time="2020-11-12T15:01:33Z" level=error msg="failed to reconcile request /default: failed to ensure dns default: failed to create service for dns default: failed to create dns service: Service \"dns-default\" is invalid: spec.clusterIP: Invalid value: \"192.168.1.10\": provided IP is already allocated"
```

and delete the offending service. You can check with: `òc get svc -A | grep 192.168.1.10`

```bash
root@ubuntu:/etc/nginx# oc get svc -A | grep 192.168.1.10
openshift-authentication                           oauth-openshift                            ClusterIP   192.168.1.106   <none>        443/TCP                               15m
openshift-cluster-version                          cluster-version-operator                   ClusterIP   192.168.1.108   <none>        9099/TCP                              22m
openshift-ingress-operator                         metrics                                    ClusterIP   192.168.1.105   <none>        9393/TCP                              21m
openshift-kube-apiserver                           apiserver                                  ClusterIP   192.168.1.107   <none>        443/TCP                               15m
openshift-machine-api                              cluster-baremetal-webhook-service          ClusterIP   192.168.1.10    <none>        443/TCP                               21m
openshift-machine-config-operator                  machine-config-daemon                      ClusterIP   192.168.1.103   <none>        9001/TCP                              22m
openshift-marketplace                              marketplace-operator-metrics               ClusterIP   192.168.1.109   <none>        8383/TCP,8081/TCP                     22m
```

In my case the service was `cluster-baremetal-webhook-service` from the openshift-machine-api : `oc delete service/cluster-baremetal-webhook-service -n openshift-machine-api`

After several minutes (be patient) the cluster will finally stand up.

**You can now disable (or delete) the bootstrap machine** to reduce the load on UDF.

````bash

## Create CA

From this point, you can stop to use ROOT and start to use your account (ubuntu).

Create a directory for the CA and clone the easy-ca repository, generate the CA certificates and keys:

```bash
mkdir /usr/share/nginx/html/installations/CA
cd /usr/share/nginx/html/installations/CA

git clone https://github.com/softark/easy-ca.git
cd easy-ca
./create-root-ca -d demo.f5.com
````

Configure CA with your custom values and configure a passphrase.
You should see the following:

```bash
ubuntu@ocp-provisioner:/usr/share/nginx/html/installations/CA/easy-ca$ ./create-root-ca -d demo.f5.com
[*] Creating root CA in dir 'demo.f5.com'
[*] Initializing CA home
[>] Enable PKCS11 Engine for this CA? [y/N]: N
[>] Short label for new CA [demo.f5.com]: demo.f5.com
[>] Domain name for new CA [bogus.com]: demo.f5.com

[!] CRL URL will be https://demo.f5.com/ca/demo-f5-com.crl

[>] Country code for new certificates [US]: IT
[>] State for new certificates [California]: Italy
[>] City for new certificates [San Francisco]: Milano
[>] Organization for new certificates [Bogus Inc.]: F5
[>] Organization unit for new certificates [Operations]: SE
[>] Common Name for CA certificate [F5 Certificate Authority]: F5 Certificate Authority

[>] Enter passphrase for encrypting root CA key: pass
[>] Verifying - Enter passphrase for encrypting root CA key: pass
[*] Creating the key (aes256 with 4096 bits)
Generating RSA private key, 4096 bit long modulus (2 primes)
...........................................................................................................................++++
...........................................................................................++++
e is 65537 (0x010001)
writing RSA key
[*] Creating SSH pub (ca/ssh/ca.ssh.pub)
[*] Example in sshd_config: TrustedUserCAKeys ca.ssh.pub
...
[*] Creating the root CA csr

[*] Creating the root CA certificate
Using configuration from ca/ca.conf
...
Certificate is to be certified until May 18 16:12:59 2028 GMT (1826 days)

Write out database with 1 new entries
Data Base Updated


[*] Creating the root CA CRL
Using configuration from ca/ca.conf

[*] Copying toolchain
[!] Root CA initialized.
```

## Create and install default ingress certificate with new CA

This follows <https://docs.openshift.com/container-platform/4.6/security/certificates/replacing-default-ingress-certificate.html>

Create certificates and keys for default ingress certificate:

```bash
cd /usr/share/nginx/html/installations/CA/easy-ca/demo.f5.com
bin/create-server -s "Default ingress certificate" -a apps.ocp.f5-udf.com -a "*.apps.ocp.f5-udf.com"
```

Configure certs with default values and enter your passphrase created before:

```bash
# All inputs are default - passphrase needed

[ubuntu@ocp-provisioner:/usr/share/nginx/html/installations/CA/easy-ca/demo.f5.com$ bin/create-server -s "Default ingress certificate" -a apps.ocp.f5-udf.com -a "*.apps.ocp.f5-udf.com"
[*] Creating new SSL server certificate for:
[*] commonName       Default ingress certificate
[*] subjectAltName   DNS:apps.ocp.f5-udf.com, DNS:*.apps.ocp.f5-udf.com

[>] Enter passphrase for signing CA key: pass
RSA key ok
[>] State for new certificates [Italy]:
[*] Using default CA_SERVER_CERT_ST : Italy
[>] City for new certificates [Milano]:
[*] Using default CA_SERVER_CERT_L : Milano
[>] Organization unit for new certificates [SE]:
[*] Using default CA_SERVER_CERT_OU : SE
[*] Usually a server key will not be on a pkcs11 device.
[>] Create csr on pkcs11 device? (key must be in "PIV AUTH key" or 9a) [y/N]:
[*] Using default CA_USE_PKCS11 : N
[*] Creating the server key and csr
Generating a RSA private key
...................................................................................++++
.....................................++++
writing new private key to 'certs/server/Default-ingress-certificate/Default-ingress-certificate.key'
-----
RSA key ok
[*] Example known_hosts: @cert-authority *.example.com ca.ssh-cert.pub
[*] Example sshd_config: HostCertificate Default-ingress-certificate.ssh-cert.pub
[*] Example sshd_config: TrustedUserCAKeys ca.ssh.pub
[*] Example sshd_config: RevokedKeys revoked-keys
writing RSA key
[*] Creating the server certificate
Using configuration from ca/ca.conf
Check that the request matches the signature
Signature ok
...
Certificate is to be certified until May 18 16:15:27 2028 GMT (1826 days)

Write out database with 1 new entries
Data Base Updated
[*] Verifying certificate/key pair
[*] Verifying trusted chain
certs/server/Default-ingress-certificate/Default-ingress-certificate.crt: OK
[!] Server certificate for 'Default ingress certificate' created.

# Certificate generated
```

Configure the cluster to use the new CA and certificate:

```bash
ln -s ca/ca.crt ca-bundle.crt
oc create configmap custom-ca --from-file=ca-bundle.crt -n openshift-config
oc patch proxy/cluster --type=merge --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'
oc create secret tls ingress-secret --cert=certs/server/Default-ingress-certificate/Default-ingress-certificate.crt --key=./certs/server/Default-ingress-certificate/Default-ingress-certificate.key -n openshift-ingress
oc patch ingresscontroller.operator default --type=merge -p '{"spec":{"defaultCertificate": {"name": "ingress-secret"}}}' -n openshift-ingress-operator
```

Wait until all the cluster operators are AVAILABLE

```bash
watch oc get co
```

This takes quite a long time and you might find some authentication errors in the process

## Create and install API certificate with new CA

This follows <https://docs.openshift.com/container-platform/4.6/security/certificates/api-server.html>

Create certificates and keys for API certificate:

```bash
cd /usr/share/nginx/html/installations/CA/easy-ca/demo.f5.com
bin/create-server -s "API certificate" -a api.ocp.f5-udf.com
```

Configure certs with default values and enter your passphrase created before:

```bash
ubuntu@ocp-provisioner:/usr/share/nginx/html/installations/CA/easy-ca/demo.f5.com$ bin/create-server -s "API certificate" -a api.ocp.f5-udf.com
[*] Creating new SSL server certificate for:
[*] commonName       API certificate
[*] subjectAltName   DNS:api.ocp.f5-udf.com

[>] Enter passphrase for signing CA key: pass
RSA key ok
[>] State for new certificates [Italy]:
[*] Using default CA_SERVER_CERT_ST : Italy
[>] City for new certificates [Milano]:
[*] Using default CA_SERVER_CERT_L : Milano
[>] Organization unit for new certificates [SE]:
[*] Using default CA_SERVER_CERT_OU : SE
[*] Usually a server key will not be on a pkcs11 device.
[>] Create csr on pkcs11 device? (key must be in "PIV AUTH key" or 9a) [y/N]:
[*] Using default CA_USE_PKCS11 : N
[*] Creating the server key and csr
Generating a RSA private key
...........................................................++++
....................................++++
writing new private key to 'certs/server/API-certificate/API-certificate.key'
-----
RSA key ok
[*] Example known_hosts: @cert-authority *.example.com ca.ssh-cert.pub
[*] Example sshd_config: HostCertificate API-certificate.ssh-cert.pub
[*] Example sshd_config: TrustedUserCAKeys ca.ssh.pub
[*] Example sshd_config: RevokedKeys revoked-keys
writing RSA key
[*] Creating the server certificate
Using configuration from ca/ca.conf
...
Certificate is to be certified until May 18 16:19:34 2028 GMT (1826 days)

Write out database with 1 new entries
Data Base Updated
[*] Verifying certificate/key pair
[*] Verifying trusted chain
certs/server/API-certificate/API-certificate.crt: OK
[!] Server certificate for 'API certificate' created.
```

Run the following commands to apply the new certificate to the cluster:

```bash
oc create secret tls custom-ca-api-secret --cert=certs/server/API-certificate/API-certificate.crt --key=certs/server/API-certificate/API-certificate.key -n openshift-config

oc patch apiserver cluster --type=merge -p '{"spec":{"servingCerts": {"namedCertificates": [{"names": ["api.ocp.f5-udf.com"], "servingCertificate": {"name": "custom-ca-api-secret"}}]}}}'
```

Again, watch cluster's operators evolve (it takes time to kick off):

```bash
watch oc get co
```

At some time, the command will return `Unable to connect to the server: x509: certificate signed by unknown authority`. When you will not be able to see oc components for 30 seconds, then go to the next step.

### Install certs in client

Update the trusted CAs

```bash
cat certs/server/Default-ingress-certificate/Default-ingress-certificate.crt ca/ca.crt | sudo tee /usr/local/share/ca-certificates/Default-ingress-certificate-bundle.crt
cat certs/server/API-certificate/API-certificate.crt ca/ca.crt | sudo tee /usr/local/share/ca-certificates/API-certificate.bundle.crt
cat ca-bundle.crt | sudo tee /usr/local/share/ca-certificates/openshift-ca.crt

sudo update-ca-certificates
```

And login to the cluster with new CA:

```bash
oc login -u kubeadmin -p $(cat /usr/share/nginx/html/installations/auth/kubeadmin-password) --certificate-authority=/usr/local/share/ca-certificates/openshift-ca.crt
```

The above should log in without complaining about the CA.

<details>
  <summary>Another approach if something goes wrong (alternative, just for reference)</summary>

From any node, copy `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem` into ocp-provider's folder `/usr/local/share/ca-certificates/` and run

```bash
sudo update-ca-certificates
```

</details>

## Installing a basic IdP and setup token expiration to 30 days

```bash
mkdir -p /usr/share/nginx/html/installations/IdP
cd /usr/share/nginx/html/installations/IdP
htpasswd -c -B -b users.htpasswd f5admin f5admin
oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config

oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  tokenConfig:
    accessTokenMaxAgeSeconds: 2592000
  identityProviders:
  - name: myHtpasswdProvider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF

oc adm policy add-cluster-role-to-user cluster-admin f5admin
```

It is normal to see some warnings about f5admin supossedly not existing yet

### Verify Idp

Again, watch cluster's operators evolve:

```bash
watch oc get co
```

Wait few seconds if the following doesn't work:

```bash
oc login -u f5admin -p f5admin --certificate-authority=/usr/local/share/ca-certificates/openshift-ca.crt
```

## Install NFS and Local Registry

Install and configure NFS on **ocp-provisioner**:

```bash
sudo mkdir -p /media/registry
sudo chown -R nobody:nogroup /media/registry/
sudo chmod 777 /media/registry/
echo "/media/registry *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -a
sudo exportfs -r
sudo systemctl restart nfs-kernel-server.service
sudo systemctl enable nfs-kernel-server.service
sudo systemctl status nfs-kernel-server.service
```

Create Persisten Volume Claim

```yaml
oc apply -n openshift-image-registry -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-registry
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteOnce
  nfs:
    path: /media/registry
    server: 10.1.1.4
  persistentVolumeReclaimPolicy: Retain
EOF

oc apply -n openshift-image-registry -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-registry
spec:
  accessModes:
   - ReadWriteOnce
  resources:
   requests:
    storage: 25Gi
  volumeName: pv-registry
  storageClassName: ""
EOF
```

Configure registry:

```bash
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"defaultRoute":true, "rolloutStrategy":"Recreate", "storage":{"pvc":{"claim":"pvc-registry"}}, "managementState": "Managed"}}'
```

Wait until all the cluster operators are AVAILABLE

```bash
watch oc get co
```

## Install helm3 in the provisioner

```bash
mkdir /usr/share/nginx/html/installations/Helm3
cd /usr/share/nginx/html/installations/Helm3

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

chmod og-r /usr/share/nginx/html/installations/auth/kubeconfig

helm repo add stable https://charts.helm.sh/stable
helm repo update
```

## Install Docker

Add Docker’s official GPG key:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

Use the following command to set up the repository:

```bash
echo \
 "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
 "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
 sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Update repository and install Docker Engine:

```bash
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Configure Docker to run with Ubuntu user:

```bash
echo "alias podman=docker" | tee -a /home/ubuntu/.bashrc
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
source /home/ubuntu/.bashrc
```

Then test it:

```bash
docker pull nginx

registry=default-route-openshift-image-registry.apps.ocp.f5-udf.com/registry-images
docker tag nginx $registry/nginx
oc login -u f5admin -p f5admin
oc create ns registry-images
docker login -u f5admin -p $(oc whoami -t) default-route-openshift-image-registry.apps.ocp.f5-udf.com
docker push $registry/nginx
```

## Thanks

Paolo: <https://github.com/tomminux/f5-udf-ocp-baremetal-blueprint/blob/main/docs/procedure.md>
Alfonso: Internal Guide
