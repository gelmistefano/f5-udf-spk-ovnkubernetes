#!/bin/bash

# This script is used to install the SPK program in automatic way.

echo "Verify SPK and JWT files exist"

file1="/home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/SPK_1_5_0.zip"
file2="/home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spk-eval.jwt"

if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
    echo "Error: SPK_1_5_0.zip or spk-eval.jwt not found."
    exit 1
fi

oc login -u f5admin -p f5admin --insecure-skip-tls-verify > /dev/null 2>&1

oclogin=$(oc whoami 2>&1)

if [[ $oclogin == *"f5admin"* ]]; then
  echo "Logged in as f5admin"
else
  echo "Error: Not logged in as f5admin into OCP Cluster"
  exit 1
fi

mkdir /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spkinstall
unzip -d spkinstall SPK_1_5_0.zip > /dev/null 2>&1

cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spkinstall

output=$(openssl dgst -verify f5-spk-1.5.0.pem -keyform PEM -sha512 \
-signature f5-spk-tarball.tgz-1.5.0.sha512.sig \
f5-spk-tarball-1.5.0.tgz 2>&1)

if [[ $output == *"OK"* ]]; then
  echo "Signature f5-spk-tarball.tgz-1.5.0.sha512.sig is valid"
else
  echo "Signature f5-spk-tarball.tgz-1.5.0.sha512.sig is invalid"
  exit 1
fi

output=$(openssl dgst -verify f5-spk-1.5.0.pem -keyform PEM -sha512 \
-signature f5-spk-tarball-sha512.txt-1.5.0.sha512.sig \
f5-spk-tarball-1.5.0.tgz 2>&1)

if [[ $output == *"OK"* ]]; then
  echo "Signature f5-spk-tarball-sha512.txt-1.5.0.sha512.sig is valid"
else
  echo "Signature f5-spk-tarball-sha512.txt-1.5.0.sha512.sig is invalid"
  exit 1
fi

tar xvf f5-spk-tarball-1.5.0.tgz > /dev/null 2>&1
tar xvf f5-spk-images-1.5.0.tgz > /dev/null 2>&1

echo "Install CRDs"

tar xvf f5-spk-crds-common-3.0.2.tgz > /dev/null 2>&1
oc apply -f f5-spk-crds-common/crds > /dev/null 2>&1
tar xvf f5-spk-crds-service-proxy-3.0.2.tgz > /dev/null 2>&1
oc apply -f f5-spk-crds-service-proxy/crds > /dev/null 2>&1

echo "Upload the images"

docker load -i tar/spk-docker-images.tgz > /dev/null 2>&1
oc new-project spk-ingress > /dev/null 2>&1

docker images | grep local.registry/ | awk '{print $1":"$2}' | cut -d'/' -f2 | while read -r image; do docker tag local.registry/$image default-route-openshift-image-registry.apps.ocp.f5-udf.com/spk-ingress/$image > /dev/null 2>&1; done
docker images | grep /spk-ingress/ | awk '{print $1":"$2}' | while read -r image; do docker push $image > /dev/null 2>&1; done

echo "Creating the Secrets"

mkdir /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spkinstall/grpc_secrets
cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spkinstall/grpc_secrets

openssl genrsa -out grpc-ca.key 4096 > /dev/null 2>&1
openssl req -x509 -new -nodes -key grpc-ca.key -sha256 -days 365 -out grpc-ca.crt \
-subj "/C=US/ST=WA/L=Seattle/O=F5/OU=Dev/CN=ca" > /dev/null 2>&1

echo "[req_ext]" > server.ext
echo " " >> server.ext
echo "subjectAltName = @alt_names" >> server.ext
echo " " >> server.ext
echo "[alt_names]" >> server.ext
echo " " >> server.ext
echo "DNS.1 = grpc-svc" >> server.ext
echo "DNS.2 = otel-collector" >> server.ext

openssl genrsa -out grpc-server.key 4096 > /dev/null 2>&1
openssl req -new -key grpc-server.key -out grpc-server.csr \
-subj "/C=US/ST=WA/L=Seattle/O=F5/OU=PD/CN=f5net.com" > /dev/null 2>&1
openssl x509 -req -in grpc-server.csr -CA grpc-ca.crt -CAkey grpc-ca.key \
-CAcreateserial -out grpc-server.crt -extensions req_ext -days 365 -sha256 \
-extfile server.ext > /dev/null 2>&1

openssl genrsa -out grpc-otel-server.key 4096 > /dev/null 2>&1
openssl req -new -key grpc-otel-server.key -out grpc-otel-server.csr \
-subj "/C=US/ST=WA/L=Seattle/O=F5/OU=PD/CN=f5net.com" > /dev/null 2>&1
openssl x509 -req -in grpc-otel-server.csr -CA grpc-ca.crt -CAkey grpc-ca.key \
-set_serial 101 -outform PEM -out grpc-otel-server.crt -extensions req_ext -days 365 \
-sha256 -extfile server.ext > /dev/null 2>&1

echo "[req_ext]" > client.ext
echo " " >> client.ext
echo "subjectAltName = @alt_names" >> client.ext
echo " " >> client.ext
echo "[alt_names]" >> client.ext
echo " " >> client.ext
echo "email.1 = clientcert@f5net.com" >> client.ext

openssl genrsa -out grpc-client.key 4096 > /dev/null 2>&1
openssl req -new -key grpc-client.key -out grpc-client.csr \
-subj "/C=US/ST=WA/L=Seattle/O=F5/OU=PD/CN=f5net.com" > /dev/null 2>&1
openssl x509 -req -in grpc-client.csr -CA grpc-ca.crt -CAkey grpc-ca.key \
-set_serial 101 -outform PEM -out grpc-client.crt -extensions req_ext -days 365 \
-sha256 -extfile client.ext > /dev/null 2>&1

openssl genrsa -out grpc-otel-client.key 4096 > /dev/null 2>&1
openssl req -new -key grpc-otel-client.key -out grpc-otel-client.csr \
-subj "/C=US/ST=WA/L=Seattle/O=F5/OU=PD/CN=f5net.com" > /dev/null 2>&1
openssl x509 -req -in grpc-otel-client.csr -CA grpc-ca.crt -CAkey grpc-ca.key \
-set_serial 101 -outform PEM -out grpc-otel-client.crt -extensions req_ext -days 365 \
-sha256 -extfile client.ext > /dev/null 2>&1

openssl base64 -A -in grpc-ca.crt -out grpc-ca-encode.crt > /dev/null 2>&1
openssl base64 -A -in grpc-server.crt -out grpc-server-encode.crt > /dev/null 2>&1
openssl base64 -A -in grpc-client.crt -out grpc-client-encode.crt > /dev/null 2>&1
openssl base64 -A -in grpc-server.key -out grpc-server-encode.key > /dev/null 2>&1
openssl base64 -A -in grpc-ca.key -out grpc-ca-encode.key > /dev/null 2>&1
openssl base64 -A -in grpc-client.key -out  grpc-client-encode.key > /dev/null 2>&1
openssl base64 -A -in grpc-otel-client.crt -out grpc-otel-client-encode.crt > /dev/null 2>&1
openssl base64 -A -in grpc-otel-server.crt -out grpc-otel-server-encode.crt > /dev/null 2>&1
openssl base64 -A -in grpc-otel-client.key -out grpc-otel-client-encode.key > /dev/null 2>&1
openssl base64 -A -in grpc-otel-server.key -out grpc-otel-server-encode.key > /dev/null 2>&1

echo "apiVersion: v1" > keys-secret.yaml
echo "kind: Secret" >> keys-secret.yaml
echo "metadata:" >> keys-secret.yaml
echo " name: keys-secret" >> keys-secret.yaml
echo "data:" >> keys-secret.yaml
echo -n " priv.key: " >> keys-secret.yaml; cat grpc-ca-encode.key >> keys-secret.yaml
echo "" >> keys-secret.yaml
echo -n " grpc-svc.key: " >> keys-secret.yaml; cat grpc-server-encode.key >> keys-secret.yaml
echo "" >> keys-secret.yaml
echo -n " f5-ing-demo-f5ingress.key: " >> keys-secret.yaml; cat grpc-client-encode.key >> keys-secret.yaml
echo "" >> keys-secret.yaml
echo -n " grpc-otel-client.key: " >> keys-secret.yaml; cat grpc-otel-client-encode.key >> keys-secret.yaml
echo "" >> keys-secret.yaml
echo -n " grpc-otel-server.key: " >> keys-secret.yaml; cat grpc-otel-server-encode.key >> keys-secret.yaml

echo "apiVersion: v1" > certs-secret.yaml
echo "kind: Secret" >> certs-secret.yaml
echo "metadata:" >> certs-secret.yaml
echo " name: certs-secret" >> certs-secret.yaml
echo "data:" >> certs-secret.yaml
echo -n " ca_root.crt: " >> certs-secret.yaml; cat grpc-ca-encode.crt >> certs-secret.yaml
echo "" >> certs-secret.yaml
echo -n " grpc-svc.crt: " >> certs-secret.yaml; cat grpc-server-encode.crt >> certs-secret.yaml
echo "" >> certs-secret.yaml
echo -n " f5-ing-demo-f5ingress.crt: " >> certs-secret.yaml; cat grpc-client-encode.crt >> certs-secret.yaml
echo "" >> certs-secret.yaml
echo -n " grpc-otel-client.crt: " >> certs-secret.yaml; cat grpc-otel-client-encode.crt >> certs-secret.yaml
echo "" >> certs-secret.yaml
echo -n " grpc-otel-server.crt: " >> certs-secret.yaml; cat grpc-otel-server-encode.crt >> certs-secret.yaml

oc adm policy add-scc-to-user privileged -n spk-ingress -z default > /dev/null 2>&1

oc apply -f keys-secret.yaml -n spk-ingress > /dev/null 2>&1
oc apply -f certs-secret.yaml -n spk-ingress > /dev/null 2>&1

echo "Create cluster Secrets and CWC certificates"

cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spkinstall
tar xvf tar/f5-cert-gen-0.2.4.tgz > /dev/null 2>&1

oc new-project spk-telemetry > /dev/null 2>&1
sh cert-gen/gen_cert.sh -s=api-server -a=f5-spk-cwc.spk-telemetry -n=1 > /dev/null 2>&1

oc apply -f cwc-license-certs.yaml -n spk-telemetry > /dev/null 2>&1

sh cert-gen/gen_cert.sh -s=rabbit \
-a=rabbitmq-server.spk-telemetry.svc.cluster.local \
-n=3 > /dev/null 2>&1

oc apply -f rabbitmq-client-certs.yaml -n spk-telemetry > /dev/null 2>&1
oc apply -f rabbitmq-server-certs.yaml -n spk-telemetry > /dev/null 2>&1

oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cpcl-crt-cm
data:
  jwt_ca.crt: |+
    -----BEGIN CERTIFICATE-----
    MIIDbzCCAlegAwIBAgIBATANBgkqhkiG9w0BAQsFADA1MQswCQYDVQQGEwJTRTEU
    MBIGA1UEChMLQ29tcGFueSBDby4xEDAOBgNVBAMTB1Jvb3QgQ0EwHhcNMjEwNzA1
    MTQzMzEzWhcNMzEwNzA1MTQzMzIzWjAxMQswCQYDVQQGEwJTRTEUMBIGA1UEChML
    Q29tcGFueSBDby4xDDAKBgNVBAMTA0RDQTCCASIwDQYJKoZIhvcNAQEBBQADggEP
    ADCCAQoCggEBAMlzVdnBKDTmZy6yCQ9qw9OyYWh0lq5nD126LFX2UyZbIR2sNrpt
    WiTLizaxA0snf24Ha3nSA8MWraxuh8p1x0IEF8J+FsOpCzSWlU3P1C1bThWnkmco
    aJx/dGMtNHMhHWJn8bowUKFmSFLGL3wYWZbjoRWHuwaW3P0WqGqTo82ttjQPhK7u
    RW/U0OP+G9tkZAJXGQdaJseO8Km8Sfvw62xUgG28GXOiL2nNLEW5Jqg5FB8Ib/dB
    RtclIte87nf9uK/5KOJadzdthQeFmrBUzizE5mQTtegUiHUaNrXDAWdeljD4HMCy
    Z47SoghEaDVuJwcaDKUxIfC1PtOQnCbmZ1kCAwEAAaOBjTCBijAOBgNVHQ8BAf8E
    BAMCAQYwEwYDVR0lBAwwCgYIKwYBBQUHAwEwEgYDVR0TAQH/BAgwBgEB/wIBATAd
    BgNVHQ4EFgQUFh1AknXyhoLd03dQppbVU3GAryowHwYDVR0jBBgwFoAUFzn9dWIf
    8WQzkjGqZs2jDKtk6TYwDwYDVR0RBAgwBocEfwAAATANBgkqhkiG9w0BAQsFAAOC
    AQEAkxBkFBuxvFCZL4/bWSlpHJKo7UCbcASzuMbdMThgf6OPYx+ggmuQZh3+DZ/4
    rTvf6YRrSYuceuF2c26tlknhT9uehYdz4Q/75RFzhwT4PvmUZ6agRJB5I9FsdjBN
    Q101ew1t6aPmoGPViiosEYVWIRf/0du/WycorNMh3WMo7cZ9+UuBkgehVYz0rxyO
    sOf0apgk+oLC04RmoUkVU5AVX/5xWSA0o++SHlv3tkKoCRooE/G7ke7ie18bjCr0
    laFS3U1i0dcEPMTvy0+kkwrkO/1onZRhzOTk1E7AsAlHlwe78p3g26JaZ3d+IzJM
    ommDCLNJvSoo3MUxEqVKsIgEvw==
    -----END CERTIFICATE-----
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cpcl-key-cm
data:
  jwt.key: |+
    {
      "keys": [
        {
          "kid": "v1",
          "alg": "RS512",
          "kty": "RSA",
          "n": "wgqDv-fuebdh_gV3wN8voRGcHGDo4YekYT78U2x-gAgxWDFFP4uIpQk9d_Hszevyr78xgFBD7RnR4FeWu7R62L1DnEEbrQYEjNI1quLtcfI5wvfdMLeyv5ZXe4-Uu21lwhvRtJCyzNRW797NPaVsMAzrcWwslHZdrljgbLaf3UX90ITyqd9MFgb7jNmRLjdzZLDqQjyYJTq2AOaAoagX0pqKkBWGlgNbiFAuV2RMUhis9Ei5NSfiD5I5ntsvp_Q_XxcJrYrJOs9uaXkeTMXa58JUeX7Tt6zLA6Ju1wxClYMyNWj4u5dG8u2yhCrucJ2_IvTs4A1BSOfAWW5TwS8BBYuY9H_OXgoqyYybeOU5YOHmszaDXfMs7FFZkjAFIfr95bprH-HW1cwREQ_eqkYxi9XmA3KCNQGLhZ_i9gRTu8MlGwYzckeJG_NOyPIa7WRw7zFe7RHcchqaCSjpWC4u-GSZ92uf-EUw2Db7OX4J8VcD_3cvCfCEzfsrSaTkLZvlkYLC-3x4eM7B2GiM7SA8l4u0DK0nrScLsOR5njd2IUUB38K39Jq-tlD5PoqLT6u0AE4IJtWN-S6uFhqzdUvExBYK19ZhTbeMmOEkMALlEPhsNUnOSXGnocxlsRYldwfCoNtpVYxlXrSnbHkuPlK8Q27yi1wO9r3RwO_OxQnUvXk",
          "e": "AQAB",
          "x5c": [
            "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"
          ],
          "use": "sig"
        }
      ]
    }
EOF

echo "Install the CWC"

oc adm policy add-scc-to-user privileged -n spk-telemetry -z default > /dev/null 2>&1

cat <<EOF > cwc-values.yaml
image:
  repository: "default-route-openshift-image-registry.apps.ocp.f5-udf.com/spk-ingress"
EOF

oc create secret docker-registry f5ingress-regsecret \
    --docker-server=default-route-openshift-image-registry.apps.ocp.f5-udf.com \
    --docker-username=f5admin \
    --docker-password=$(oc whoami -t) > /dev/null 2>&1

helm install spk-cwc tar/cwc-0.4.15.tgz -f cwc-values.yaml \
--set cpclConfig.jwt=$(cat /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spk-eval.jwt) -n spk-telemetry > /dev/null 2>&1

echo "License"

echo "10.1.1.9 f5-spk-cwc.spk-telemetry" | sudo tee -a /etc/hosts
cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spkinstall/api-server-secrets/ssl/

echo "Wait until cwc is ready"

while ! nc -z "f5-spk-cwc.spk-telemetry" "30881"; do
    sleep 1
done

echo "CWC is ready, start licensing process"

sleep 30

DIGITALASSETID=$(curl -s --cert client/certs/client_certificate.pem --key client/secrets/client_key.pem --cacert ca/certs/ca_certificate.pem https://f5-spk-cwc.spk-telemetry:30881/status | jq '.InitialRegistrationStatus.LicenseDetails.DigitalAssetID')

REPORT=$(curl -s --cert client/certs/client_certificate.pem --key client/secrets/client_key.pem --cacert ca/certs/ca_certificate.pem https://f5-spk-cwc.spk-telemetry:30881/report | jq '.report')

MANIFEST=$(curl -s --cert client/certs/client_certificate.pem --key client/secrets/client_key.pem --cacert ca/certs/ca_certificate.pem https://product.apis.f5.com/ee/v1/entitlements/telemetry -H "Content-Type: application/json" -H "F5-DigitalAssetId: $DIGITALASSETID" -H "User-Agent: SPK" -H "Authorization: Bearer $(cat /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/spk-eval.jwt)" -d "{\"report\":$REPORT}" | jq '.manifest')

curl -s --cert client/certs/client_certificate.pem --key client/secrets/client_key.pem --cacert ca/certs/ca_certificate.pem https://f5-spk-cwc.spk-telemetry:30881/receipt -d ${MANIFEST:1:-1}

sleep 30

licensestatus=$(curl -s --cert client/certs/client_certificate.pem --key client/secrets/client_key.pem --cacert ca/certs/ca_certificate.pem https://f5-spk-cwc.spk-telemetry:30881/status | jq '.Status.LicenseStatus.State')

if [ "$licensestatus" == "\"Verification Complete\"" ]; then
    echo "License is valid, install SPK"
else
    echo "License is not valid"
    exit 1
fi

oc new-project demoapp > /dev/null 2>&1
oc project spk-ingress > /dev/null 2>&1

oc patch networks.operator.openshift.io cluster --type=merge --patch='{
  "spec": {
    "additionalNetworks": [
      {
        "name": "internal-spk",
        "namespace": "spk-ingress",
        "rawCNIConfig": "{\n  \"cniVersion\": \"0.3.1\",\n  \"name\": \"internal-spk\",\n  \"type\": \"macvlan\",\n  \"master\": \"br-ex\",\n  \"mode\": \"bridge\"\n}",
        "type": "Raw"
      },
      {
        "name": "external-spk",
        "namespace": "spk-ingress",
        "rawCNIConfig": "{\n  \"cniVersion\": \"0.3.1\",\n  \"name\": \"external-spk\",\n  \"type\": \"macvlan\",\n  \"master\": \"enp0s5\",\n  \"mode\": \"bridge\"\n}",
        "type": "Raw"
      }
    ]
  }
}'

sudo snap install yq

cd /home/ubuntu/f5-udf-spk-ovnkubernetes/SPK/
RUNTIMECLASSNAME=$(oc get performanceprofile -o jsonpath='{..runtimeClass}{"\n"}')
RABBITMQCERTS_CA=$(cat ./spkinstall/rabbitmq-client-1-certs.yaml | yq '.data."ca-root-cert.pem"')
RABBITMQCERTS_CERT=$(cat ./spkinstall/rabbitmq-client-1-certs.yaml | yq '.data."client-cert.pem"')
RABBITMQCERTS_KEY=$(cat ./spkinstall/rabbitmq-client-1-certs.yaml | yq '.data."client-key.pem"')

yq e -i ".tmm.runtimeClassName = \"$RUNTIMECLASSNAME\"" ingress-values.yaml
yq e -i ".controller.f5_lic_helper.rabbitmqCerts.ca_root_cert = \"$RABBITMQCERTS_CA\"" ingress-values.yaml
yq e -i ".controller.f5_lic_helper.rabbitmqCerts.client_cert = \"$RABBITMQCERTS_CERT\"" ingress-values.yaml
yq e -i ".controller.f5_lic_helper.rabbitmqCerts.client_key = \"$RABBITMQCERTS_KEY\"" ingress-values.yaml

sed -i "s/f5admin_token/$(oc whoami -t)/g" ingress-values.yaml

cd spkinstall
oc project spk-ingress > /dev/null 2>&1
helm install f5ingress tar/f5ingress-5.0.29.tgz -f ../ingress-values.yaml > /dev/null 2>&1

echo "SPK Installed, verify with: oc get pods -n spk-ingress"