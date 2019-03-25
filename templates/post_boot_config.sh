#!/usr/bin/env bash

kubectl create -f $HOME/local_storage_pv.yaml
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --history-max 200
git clone https://github.com/hashicorp/consul-helm.git
cd consul-helm
git checkout v0.6.0
helm template . -f $HOME/helm_consul_values.yaml > $HOME/consul.yaml
sed -i "s/# Consul agents require a directory for data, even clients./dnsPolicy: ClusterFirstWithHostNet\n      hostNetwork: true\n      # Consul agents require a directory for data, even clients./g" $HOME/consul.yaml
kubectl apply -f $HOME/consul.yaml
sleep 3

# Update the DNS records to ensure 'consul' dns is setup.
kubectl get configmap coredns -n kube-system -o yaml > $HOME/coredns.yaml
sed -i "s/Corefile: |/Corefile: |\n    consul:53 {\n      errors\n      cache 30\n      proxy . $(kubectl get svc | grep consul-dns | awk '{print $3}')\n    }/g" $HOME/coredns.yaml
kubectl apply -f $HOME/coredns.yaml
kubectl delete pods -l k8s-app=kube-dns -n kube-system