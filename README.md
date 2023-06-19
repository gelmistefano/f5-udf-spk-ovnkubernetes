# F5 UDF Deployment for SPK w/ OVNKubernetes

This guide explain how to install and use for demo F5 SPK with OCP and OVNKubernetes.
_NB: This guide is created for [SPK 1.5.0](https://clouddocs.f5.com/service-proxy/1.5.0/spk-software-install.html)_

## Prerequisites

- OCP 4.11 with OVNKubernetes - You can find the guide [here](ocp-deploy/README.md)
- SPK Binaries (zip file)
- License JWT file

## Requirements

Configure Hugepages and single-numa-node on one (or more) nodes. To do that, select which nodes you want to enable them with a label with command:
`oc label node <node-selected> node-role.kubernetes.io/worker-hp=`
Here an example for node worker-1:

```bash
ubuntu@ocp-provisioner:~$ oc get nodes
NAME                      STATUS   ROLES    AGE     VERSION
master-1.ocp.f5-udf.com   Ready    master   3h24m   v1.24.0+dc5a2fd
master-2.ocp.f5-udf.com   Ready    master   3h24m   v1.24.0+dc5a2fd
master-3.ocp.f5-udf.com   Ready    master   3h24m   v1.24.0+dc5a2fd
worker-1.ocp.f5-udf.com   Ready    worker   3h9m    v1.24.0+dc5a2fd
worker-2.ocp.f5-udf.com   Ready    worker   3h9m    v1.24.0+dc5a2fd
worker-3.ocp.f5-udf.com   Ready    worker   3h9m    v1.24.0+dc5a2fd

ubuntu@ocp-provisioner:~$ oc label node worker-1.ocp.f5-udf.com node-role.kubernetes.io/worker-hp=
node/worker-1.ocp.f5-udf.com labeled

ubuntu@ocp-provisioner:~/f5-udf-ocp-ovnKubernetes/SPK/requirements$ oc get nodes
NAME                      STATUS   ROLES              AGE     VERSION
master-1.ocp.f5-udf.com   Ready    master             3h27m   v1.24.0+dc5a2fd
master-2.ocp.f5-udf.com   Ready    master             3h27m   v1.24.0+dc5a2fd
master-3.ocp.f5-udf.com   Ready    master             3h27m   v1.24.0+dc5a2fd
worker-1.ocp.f5-udf.com   Ready    worker,worker-hp   3h12m   v1.24.0+dc5a2fd
worker-2.ocp.f5-udf.com   Ready    worker             3h12m   v1.24.0+dc5a2fd
worker-3.ocp.f5-udf.com   Ready    worker             3h11m   v1.24.0+dc5a2fd
```

Apply files in requirements:

```bash
cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/requirements

oc create -f 0-hugepages-tuned-boottime.yaml
oc create -f 1-hugepages-mcp.yaml
oc create -f 3-PerformanceProfile.yaml
```

Now, wait until nodes return up with `watch oc get nodes`.

## Automatic Installation

You can perform an automatic installation of SPK with OVNKubernetes with the script `install.sh`:

```bash
cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK
chmod +x install.sh
./install.sh
```

The following script performs all actions needed to deploy SPK TMM and integrate with OVNKubernetes. All steps are described in Manual Installation.

At the end of execution, you should see the following output:

```bash
Verify SPK and JWT files exist
Logged in as f5admin
Signature f5-spk-tarball.tgz-1.5.0.sha512.sig is valid
Signature f5-spk-tarball-sha512.txt-1.5.0.sha512.sig is valid
Install CRDs
Upload the images
Creating the Secrets
Create cluster Secrets and CWC certificates
configmap/cpcl-crt-cm created
configmap/cpcl-key-cm created
Install the CWC
License
10.1.1.9 f5-spk-cwc.spk-telemetry
Wait until cwc is ready
License is valid
network.operator.openshift.io/cluster patched
yq v4.34.1 from Mike Farah (mikefarah) installed
SPK Installed, verify with: oc get pods -n spk-ingress
```

After this step, you can verify the installation with `oc get pods -n spk-ingress`, wait until all pods are in `Running` state:

```bash
ubuntu@ocp-provisioner:~/f5-udf-spk-ovnkubernetes/SPK$ oc get pods -n spk-ingress
NAME                                   READY   STATUS    RESTARTS   AGE
f5-tmm-6795b5dcf8-sr2np                2/2     Running   0          56s
f5ingress-f5ingress-85ffc97c7f-7ww56   2/2     Running   0          56s
```

Now your SPK is installed and ready to use.

### BUG Found - cwc pod not ready

The script waits until CWC service is ready, but sometimes it fails. In this case, you can check the status of the pod with `oc get pods -n spk-telemetry` and verify the status with `oc describe pods -n spk-telemetry <CWC POD NAME>`.

## Manual Installation

If you want, you can perform manual installation to understand better all steps. You can follow the guide [here](SPK/README.md) to deploy SPK manually.

## SPK Configuration

Now SPK is deployed, you can configure it to integrate with OVNKubernetes and your applications.

### Interfaces

The F5SPKVlan Custom Resource (CR) configures the Service Proxy TMM interfaces, and should install to the same Project as the Service Proxy TMM Pod. It is important to set the F5SPKVlan spec.internal parameter to true on the internal VLAN interface to apply OVN-Kubernetes Annotations, and to select an IP address from the same subnet as the OpenShift nodes.

Configure external and internal F5SPKVlan CRs. You can place both CRs in the same YAML file:

```bash
oc apply -f - <<EOF
apiVersion: "k8s.f5net.com/v1"
kind: F5SPKVlan
metadata:
  name: internal
  namespace: spk-ingress
spec:
  name: internal
  interfaces:
    - "1.2"
  internal: true
  selfip_v4s:
    - 10.1.1.100
  prefixlen_v4: 24
EOF

oc apply -f - <<EOF
apiVersion: "k8s.f5net.com/v1"
kind: F5SPKVlan
metadata:
  name: external
  namespace: spk-ingress
spec:
  name: external
  interfaces:
    - "1.1"
  selfip_v4s:
    - 10.1.10.100
  prefixlen_v4: 24
EOF
```

## Install DemoApps

You can use two different demo applications to test the F5 Service Proxy TMM. The first is a simple web application, and the second is a more complex application that uses a database and multiple miocroservices, the last application is a simple UDP application that write in log what receives.

_NB: SPK w/ OVNKubernetes requires a separated phisical interface attached on same subnet used for MGMT and CNI to reach correctly all services that are running on same node where SPK is deployed. On UDF, we cannot do that, so we dedicate the worker-1 node to SPK and we will use ore nodes to deploy the demoapps._

### UDF requirements - Dedicate nodes for demoapps

Use all worker nodes except worker with HP to deploy demoapps. To do this, label all nodes with `node-role.kubernetes.io/worker-apps=yes`, except worker with `worker-hp` label.

Verify nodes:

```bash
ubuntu@ocp-provisioner:~$ oc get nodes
NAME                      STATUS   ROLES              AGE     VERSION
master-1.ocp.f5-udf.com   Ready    master             3d18h   v1.24.0+dc5a2fd
master-2.ocp.f5-udf.com   Ready    master             3d18h   v1.24.0+dc5a2fd
master-3.ocp.f5-udf.com   Ready    master             3d18h   v1.24.0+dc5a2fd
worker-1.ocp.f5-udf.com   Ready    worker,worker-hp   3d18h   v1.24.0+dc5a2fd
worker-2.ocp.f5-udf.com   Ready    worker             3d18h   v1.24.0+dc5a2fd
worker-3.ocp.f5-udf.com   Ready    worker             3d18h   v1.24.0+dc5a2fd
```

Label nodes (our case worker-2 and worker-3):

```bash
ubuntu@ocp-provisioner:~$ oc label node worker-2.ocp.f5-udf.com node-role.kubernetes.io/worker-apps=demo
node/worker-2.ocp.f5-udf.com labeled

ubuntu@ocp-provisioner:~$ oc label node worker-3.ocp.f5-udf.com node-role.kubernetes.io/worker-apps=demo
node/worker-3.ocp.f5-udf.com labeled

ubuntu@ocp-provisioner:~$ oc get nodes
NAME                      STATUS   ROLES                AGE     VERSION
master-1.ocp.f5-udf.com   Ready    master               3d18h   v1.24.0+dc5a2fd
master-2.ocp.f5-udf.com   Ready    master               3d18h   v1.24.0+dc5a2fd
master-3.ocp.f5-udf.com   Ready    master               3d18h   v1.24.0+dc5a2fd
worker-1.ocp.f5-udf.com   Ready    worker,worker-hp     3d18h   v1.24.0+dc5a2fd
worker-2.ocp.f5-udf.com   Ready    worker,worker-apps   3d18h   v1.24.0+dc5a2fd
worker-3.ocp.f5-udf.com   Ready    worker,worker-apps   3d18h   v1.24.0+dc5a2fd
```

### Simple Web Application - NGINX

Proceed to create privileges for the Service Account, and then deploy the NGINX DemoApp:

```bash
oc project demoapp
oc create sa nginx-sa
oc adm policy add-scc-to-user privileged -z nginx-sa
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/demoapp-nginx.yaml
```

After deployed, you can create the TCP Ingress resource with SNAT enabled:

```bash
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/ingresstcp-snat.yaml
```

Test it with `curl` command:

```bash
curl -s http://10.1.10.200 | jq
```

Result should be a JSON with source IP address of the TMM Pod:

```json
{
  "source_ip": "10.1.1.100",
  "source_port": "54256",
  "server_name": "nginx-deployment-77f748cf9-hx75h"
}
```

You can also apply the TCP Ingress resource with SNAT disabled (wait few seconds after apply the resource w/ SNAT, otherwise the CRD will be not correcly configured):

```bash
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/ingresstcp-no-snat.yaml
```

Test it with `curl` command:

```bash
curl -s http://10.1.10.201 | jq
```

Result should be a JSON with source IP address of the client:

```json
{
  "source_ip": "10.1.10.4",
  "source_port": "35168",
  "server_name": "nginx-deployment-77f748cf9-hx75h"
}
```

### Complex Application - Online Boutique

Proceed to create privileges for the Service Account, and then deploy the Online Boutique DemoApp:

```bash
oc project demoapp
oc create sa onlineboutique-sa
oc adm policy add-scc-to-user privileged -z onlineboutique-sa
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/demoapp-onlineboutique.yaml
```

After deployed, you can create the TCP Ingress resource with SNAT disabled:

```bash
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/ingresstcp-onlineboutique.yaml
```

Test it with `curl` command:

```bash
curl http://10.1.10.202
```

Result should be the HTTP response from the Online Boutique application.
You can also verify from windows Jumphost.

## DemoApp - UDP Ingress

Deploy the UDP service:

```bash
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/demoapp-udp.yaml
```

The service receives UDP packets on port 5005 and log in stdout.

Deploy the UDP Ingress resource:

```bash
oc apply -f /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/demoapp/ingressudp.yaml
```

The UDP Ingress resource receives on port 65000 forwards the UDP packets to the service.

Test it with `nc` command:

```bash
echo "Hello World" | nc -u 10.1.10.210 65000 -w 1
```

See the result in stdout of the service:

```bash
oc logs -f $(oc get po -l app=udp-listener -o jsonpath='{.items[0].metadata.name}')

Listening on UDP port 5005
Hello World
```
