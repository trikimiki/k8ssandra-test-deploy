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
  aws configure
  ```


## step 1 - create EKS cluster and get access with kubectl

```
eksctl create cluster -f eks/cluster.yml
```
```
aws eks update-kubeconfig --region ap-south-1 --name k8ssandra-test-triki
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
helm install k8ssandra-operator --version 1.23.1 k8ssandra/k8ssandra-operator \
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

you can use the following to get into `cqlsh` console:
```
kubectl -n thingsboard exec -it thingsboardcluster-datacenter1-r1a-sts-0 -c cassandra -- cqlsh -u <username>
```
to get creds:
```
kubectl -n thingsboard get secret thingsboardcluster-superuser -o json | jq -r '.data.username' | base64 --decode
kubectl -n thingsboard get secret thingsboardcluster-superuser -o json | jq -r '.data.password' | base64 --decode
```

## step 7 - create AWS RDS (Postgres) instance for thingsboard
AWS Console -> Aurora and RDS -> Create database

see [rds-params.png](rds-params.png) - crucial parameters are highlighted

__IMPORTANT__ - save master user password somewhere! you cannot read it after DB creation; we will put it inside kubernetes secret in the next step

alternatively, you can use AWS secret manager for this

## step 8 - deploy thingsboard

### 8.1 create secret with RDS creds

```
RDS_SOURCE="jdbc:postgresql://$(aws rds describe-db-instances --region ap-south-1 | jq -r '.DBInstances[] | select(.DBInstanceIdentifier == "rds-for-k8ssandra-test-triki") | .Endpoint.Address'):5432/thingsboard"
```
```
RDS_USER=$(aws rds describe-db-instances --region ap-south-1 | jq -r '.DBInstances[] | select(.DBInstanceIdentifier == "rds-for-k8ssandra-test-triki") | .MasterUsername')
```
```
RDS_PASS=<paste master password here>
```
```
kubectl create -n thingsboard secret generic rds-secrets \
  --from-literal=rds-datasource="$RDS_SOURCE" \
  --from-literal=rds-username="$RDS_USER" \
  --from-literal=rds-password="$RDS_PASS"
```

### 8.2 create thingsboard configmap

```
kubectl apply -f thingsboard/tb-node-configmap.yml
```

### 8.3 install postgres and cassandra data

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

### 8.4 create and start thingsboard app

```
kubectl apply -f thingsboard/tb-node-sts.yml
```

### 8.5 create AWS load-balancer

```
kubectl apply -f thingsboard/tb-nlb.yml
```

## step 9 access thingsboard

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