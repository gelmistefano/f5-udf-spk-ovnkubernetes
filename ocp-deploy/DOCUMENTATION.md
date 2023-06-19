# OCP 4.11 Clean w/ OVNKubernetes

This Blueprint will give you a default Openshift version 4.11 environment.
If you need to deploy a OCP Cluster like this but with different version you can follow the manual procedure here.

## Additional Openshift setup

- MGMT Interface (for cluster communication - CNI) and additional External Interface (not used in OCP - Useful for SPK)
- NFS Storage
- Image registry
- Setup of a CA (in /usr/share/nginx/html/installations/CA/easy-ca/demo.f5.com)
- Setup of DNS wildcard zones for OCP default Ingress (_.apps.ocp.f5-udf.com) and AM Ingress gateway (_.am.ocp.f5-udf.com)

This Openshift cluster has 3 masters and 3 workers. If you need more workers, you can use the master nodes with this command:
`oc patch schedulers.config.openshift.io cluster --merge --patch=mastersSchedulable: true`

## Using the Deployment

The node that is used as jumphost is named ocp-provider, it is used for CLI.

### Using the CLI

SSH into ocp-provider with login name ubuntu. From there you can run the oc and kubectl tools. You should be already logged in, but in case you can execute the following command:

```bash
oc login -u f5admin -p f5admin # the f5admin user has cluster-admin permissions
```

After login, wait until the cluster is UP:

```bash
watch oc get co
```

If after 15min you find that you are still unable to login, and you get connection problems, apply the procedure "Cluster's nodes cerficate expiration" found further down

### Using the UI

Login with RDP in the Windows jumphost node and open a browser with <https://console-openshift-console.apps.ocp.f5-udf.com/> using the HTTP auth provider and the f5admin/f5admin credentials.

### Using the registry

Sample usage from the ocp-provider host:

```bash
docker pull nginx
registry=default-route-openshift-image-registry.apps.ocp.f5-udf.com
docker tag nginx $registry/registry-images/nginx
oc login -u f5admin -p f5admin
oc create ns registry-images
docker login -u f5admin -p $(oc whoami -t) $registry
docker push $registry/registry-images/nginx
```

## Stopping the Deployment

Nothing special needs to be done. UDF stops the cluster by means of signaling the nodes and that gives plenty of time for them to shutdown orderly.

## Cluster's nodes cerficate expiration

In case you have a certificate expiration, use the following procedure

```bash
oc config use-context admin

while date ; do
  oc get csr --no-headers | grep Pending | awk '{print $1}' | xargs --no-run-if-empty oc  adm certificate approve
  sleep 5
done
```

It should allow you to approve node's CSRs

## Cluster's nodes don't start - Unable to connect to the server: EOF

If you receive error `Unable to connect to the server: EOF` during `oc login`, you need to approve CSRs directly from master node.

Login into `ocp-master-1` node with _SSH (core)_ access method and run the following commands:

```bash
sudo -i

export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
oc get csr -o name | xargs oc adm certificate approve
```

Verify if all CSRs are approved with command `oc get csr -A`

If you see any other CSRs need to be approved, run again the command `oc get csr -o name | xargs oc adm certificate approve` until all CSRs are approved.

Wait few minutes and you will be able to login into cluster with ocp-provisioner VM.

## How to get a SHELL access in the nodes?

If you need get a shell, for example to do a tcpdump, the recommended procedure is as follows:

```bash
oc debug node/worker-1.ocp.f5-udf.com
```

Additional info <https://docs.openshift.com/container-platform/4.11/support/troubleshooting/verifying-node-health.html>

## Thanks

Blueprint based on [Openshift 4.11 - OVN Kubernetes - Clean](https://udf.f5.com/b/98dba087-bf10-4376-8bb1-071b235e3184) and [Openshift - UDF Bare Metal Deployment](https://udf.f5.com/b/b6c9b97c-68c7-4fe2-942d-103c8b6468b4)
