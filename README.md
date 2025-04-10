my first shoot at deploying single-cluster k8ssandra on EKS

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

## step 4 - TBD