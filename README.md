my first shot at deploying single-cluster k8ssandra on EKS

will use [thingsboard ce](https://thingsboard.io/docs/faq/) as a platfrom to test the database

## step 1 - deploy nodes

```
eksctl create cluster -f eks/cluster.yml
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
  --set clusterName=tb-k8ssandra-test-triki \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```
```
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm install --version 1.14.4 cert-manager jetstack/cert-manager \
  -n cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.create=false \
  --set cainjector.serviceAccount.create=false
```

## step 4 - install k8ssandra-operator in cluster scoped mode
since thingsboard will need to access cassandra db, later we will deploy them in the same separate namespace
```
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo update
helm install k8ssandra-operator --version 1.21.2 k8ssandra/k8ssandra-operator \
  -n k8ssandra-operator \
  --create-namespace \
  --set global.clusterScoped=true
```

## step 5 - TBC