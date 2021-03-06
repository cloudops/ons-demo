#!/usr/bin/env bash

kubectl create -f $HOME/local_storage_pv.yaml
kubectl create -f $HOME/consul_license.yaml
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --history-max 200
git clone https://github.com/hashicorp/consul-helm.git
cd consul-helm
git checkout v0.7.0
helm template . -f $HOME/helm_consul_values.yaml > $HOME/consul.yaml
# inject the 'dnsPolicy' and 'hostNetwork' config (https://github.com/hashicorp/consul-helm/pull/44)
sed -i "s/# Consul agents require a directory for data, even clients./dnsPolicy: ClusterFirstWithHostNet\n      hostNetwork: true\n      # Consul agents require a directory for data, even clients./g" $HOME/consul.yaml
if [ "${current_dc}" != "${primary_dc}" ]
then
    line=$(grep -n "^  name: release-name-consul-server-config" $HOME/consul.yaml | cut -f1 -d:); sed -i "$(($line+9))s/{}/{\"primary_datacenter\": \"${primary_dc}\"}/g" $HOME/consul.yaml
fi
kubectl apply -f $HOME/consul.yaml
sleep 3

# Update the DNS records to ensure 'consul' dns is setup.
kubectl get configmap coredns -n kube-system -o yaml > $HOME/coredns.yaml
sed -i "s/Corefile: |/Corefile: |\n    consul:53 {\n      errors\n      cache 30\n      proxy . $(kubectl get svc | grep consul-dns | awk '{print $3}')\n    }/g" $HOME/coredns.yaml
kubectl apply -f $HOME/coredns.yaml
kubectl delete pods -l k8s-app=kube-dns -n kube-system