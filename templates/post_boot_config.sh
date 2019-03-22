#!/usr/bin/env bash

# Update the DNS records to ensure 'consul' dns is setup.
kubectl get configmap coredns -n kube-system -o yaml > $HOME/coredns.yaml
sed -i "s/Corefile: |/Corefile: |\n    consul:53 {\n      errors\n      cache 30\n      proxy . $(kubectl get svc | grep consul-dns | awk '{print $3}')\n    }/g" $HOME/coredns.yaml
kubectl apply -f $HOME/coredns.yaml
kubectl delete pods -l k8s-app=kube-dns -n kube-system