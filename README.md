my first shot at deploying single-cluster k8ssandra on EKS

will use [thingsboard ce](https://thingsboard.io/docs/faq/) as a platfrom to test the database

# INSTALLATION

## prerequisites
- setup [an AWS account](https://docs.aws.amazon.com/IAM/latest/UserGuide/getting-started-account-iam.html)
- install:
  - [kubectl](https://kubernetes.io/docs/tasks/tools/)
  - [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/setting-up.html)
  - [awscli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- configure environment:
  ```
  aws configure --profile k8ssandra-test-triki
  ```


## step 1 - create EKS cluster and get access with kubectl

```
eksctl --profile k8ssandra-test-triki create cluster -f eks/cluster.yml \
  --set-kubeconfig-context=false \
  --auto-kubeconfig=false \
  --write-kubeconfig=false
```
```
aws eks --profile k8ssandra-test-triki update-kubeconfig --region ap-south-1 --name k8ssandra-test-triki --alias k8ssandra-test-triki
```

## step 2 - create gp3 storage class, make it default

```
kubectl apply -f eks/gp3-sc.yml
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

## step 3 - install cluster dependencies
ALB controller - needed for thingsboard

cert manager - needed for cass-operator
```
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=k8ssandra-test-triki \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```
```
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm install --version 1.17.2 cert-manager jetstack/cert-manager \
  -n cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set serviceAccount.create=false \
  --set cainjector.serviceAccount.create=false
```

## step 4 - install k8ssandra-operator in cluster scoped mode
since thingsboard will need to access cassandra db, we will deploy them both in the separate namespace - need to use cluster scope
```
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo update k8ssandra
helm install k8ssandra-operator --version 1.24.0 k8ssandra/k8ssandra-operator \
  -n k8ssandra-operator \
  --create-namespace \
  --set global.clusterScoped=true
```

## step 5 - create namespace for thingsboard and cassandra

```
kubectl apply -f thingsboard/namespace.yml
```

## step 6 - deploy k8ssandra cluster

```
kubectl apply -f cassandra/k8ssandra-cluster.yml
```

## step 7 - create AWS RDS (Postgres) instance for thingsboard
AWS Console -> Aurora and RDS -> Create database

see [rds-params.png](rds-params.png) - crucial parameters are highlighted

__IMPORTANT__ - save master user password somewhere! you cannot read it after DB creation; we will put it inside kubernetes secret in the next step

alternatively, you can use AWS secret manager for this

## step 8 - deploy thingsboard

### 8.1 create secret with RDS creds

```
RDS_SOURCE="jdbc:postgresql://$(aws --profile k8ssandra-test-triki rds describe-db-instances --region ap-south-1 | jq -r '.DBInstances[] | select(.DBInstanceIdentifier == "rds-for-k8ssandra-test-triki") | .Endpoint.Address'):5432/thingsboard"
```
```
RDS_USER=$(aws rds --profile k8ssandra-test-triki describe-db-instances --region ap-south-1 | jq -r '.DBInstances[] | select(.DBInstanceIdentifier == "rds-for-k8ssandra-test-triki") | .MasterUsername')
```
```
RDS_PASS=<paste master password here>
```
```
kubectl create -n thingsboard secret generic tb-rds-secret \
  --from-literal=rds-datasource="$RDS_SOURCE" \
  --from-literal=rds-username="$RDS_USER" \
  --from-literal=rds-password="$RDS_PASS"
```

### 8.2 create cassandra keyspace
by default thingsboard installs keyspace with RF=1 - so we need to pre-install keyspace with proper RF=3

to get cassandra creds:
```
kubectl -n thingsboard get secret cassandra-superuser -o json | jq -r '.data.username' | base64 --decode
kubectl -n thingsboard get secret cassandra-superuser -o json | jq -r '.data.password' | base64 --decode
```

run query:
```
kubectl -n thingsboard exec -it cassandra-ap-south-1-r1a-sts-0 -c cassandra -- cqlsh \
              -u cassandra-superuser \
              -e \
                "CREATE KEYSPACE IF NOT EXISTS thingsboard \
                WITH replication = { \
                  'class' : 'NetworkTopologyStrategy', \
                  'ap-south-1' : '3' \
                };"
```

### 8.3 create thingsboard configmap

```
kubectl apply -f thingsboard/tb-node-configmap.yml
```

### 8.4 install postgres and cassandra data

```
cd thingsboard/install
sudo chmod +x install-tb.sh
```

```
./install-tb.sh
```

```
cd ../..
```

### 8.5 create and start thingsboard app

```
kubectl apply -f thingsboard/tb-node-sts.yml
```

## step 9 - create AWS load-balancer

```
kubectl apply -f thingsboard/tb-nlb.yml
```

## step 10 - access thingsboard

you can access web UI from browser via `EXTERNAL-IP` link from:
```
kubectl -n thingsboard get svc tb-nlb
```
default credentials are:

> System Administrator: sysadmin@thingsboard.org / sysadmin

> Tenant Administrator: tenant@thingsboard.org / tenant

> Customer User: customer@thingsboard.org / customer

# K8SSANDRA MAINTENANCE

## TBC

medusa s3 secret snippet:
```
AWS_KEY_ID=demo12345
AWS_KEY_SECRET=demo12345

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: medusa-s3-secret
  namespace: thingsboard
type: Opaque
stringData:
  credentials: |
    [default]
    aws_access_key_id = ${AWS_KEY_ID}
    aws_secret_access_key = ${AWS_KEY_SECRET}
EOF
```

TODO - check if backups arent persisted locally
TODO - instrucions for dedicated ami for medusa s3

reaper ui:
```
kubectl port-forward svc/cassandra-ap-south-1-reaper-service 8085:8080

localhost:8085/webui

kubectl get secret cassandra-reaper-ui -o jsonpath='{.data.username}' | base64 --decode
kubectl get secret cassandra-reaper-ui -o jsonpath='{.data.password}' | base64 --decode
```

manual backup:
```
DATE=$(date +%Y%m%d-%H%M) envsubst < cassandra/backup/manual.template.yml | kubectl apply -f -
```

TODO - Prometheus