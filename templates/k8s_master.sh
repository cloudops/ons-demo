#!/usr/bin/env bash

## master node on centos 7.4

## SPECS
# CentOS 7.4
# Kernel: 3.10.0-862.14.4
# CPU: 8 vCPU
# RAM: 32GB
# Root Drive: 60GB

## CLI ARGS AND VAR INIT
if [ -z "$1" ]
then
      echo "Missing 'master' private IP as first argument..."
      exit 1
fi

if [ -z "$2" ]
then
      echo "Missing 'gateway' of the underlay network as second argument..."
      exit 1
fi

TF_RELEASE="latest"
if [ -n "$3" ]
then
      TF_RELEASE="$3"
fi

TOKEN=""
if [ -n "$4" ]
then
      TOKEN="--token $4"
fi

echo "Setting up K8S Master with token: $4"

K8S_MASTER_IP=$1
VROUTER_GATEWAY=$2
TF_REPO="docker.io\/opencontrailnightly"

## SETUP PACKAGES AND SERVICES
swapoff -a
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config

sudo bash -c 'cat > /etc/yum.repos.d/kubernetes.repo' << EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

## just in case your template is ancient
#sudo yum update -y

sudo yum install -y git

sudo yum install -y ntp ntpdate
sudo ntpdate pool.ntp.org
sudo systemctl enable ntpd && sudo systemctl start ntpd

sudo yum install -y docker
sudo systemctl enable docker.service
sudo service docker start

sudo yum install -y kubelet kubeadm kubectl

## disable the default CNI
sudo sed -i 's|Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"|#Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"|g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo systemctl daemon-reload
sudo service kubelet restart

sudo systemctl enable kubelet && sudo systemctl start kubelet

sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo systemctl stop firewalld
sudo systemctl disable firewalld

echo "source <(kubectl completion bash)" >> $HOME/.bashrc

sleep 5

## INSTALL KUBERNETES
sudo kubeadm init --apiserver-cert-extra-sans $K8S_MASTER_IP $TOKEN >> $HOME/kubeadm_init.log
## uncomment to change the default `pod` and `service` networks
#sudo kubeadm init --apiserver-cert-extra-sans $K8S_MASTER_IP $TOKEN --pod-network-cidr "10.48.0.0/12" --service-cidr "10.112.0.0/12" >> $HOME/kubeadm_init.log

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config

# ## INSTALL TUNGSTEN FABRIC
# sudo mkdir -pm 777 /var/lib/contrail/kafka-logs
# curl https://raw.githubusercontent.com/Juniper/contrail-kubernetes-docs/master/install/kubernetes/templates/contrail-single-step-cni-install-centos.yaml | sed "s/{{ K8S_MASTER_IP }}/$K8S_MASTER_IP/g; s/{{ CONTRAIL_REPO }}/$TF_REPO/g; s/{{ CONTRAIL_RELEASE }}/$TF_RELEASE/g" >> tf.yaml

# ## change the `VROUTER_GATEWAY` to the underly gateway or network connectivity to the master will be lost
# sed -i "s/VROUTER_GATEWAY: $K8S_MASTER_IP/VROUTER_GATEWAY: $VROUTER_GATEWAY/g" tf.yaml

# ## uncomment to change the default `pod` and `service` networks
# #sed -i 's|KUBERNETES_API_SECURE_PORT: "6443"|KUBERNETES_API_SECURE_PORT: "6443"\n  KUBERNETES_POD_SUBNETS: 10.48.0.0/12\n  KUBERNETES_SERVICE_SUBNETS: 10.112.0.0/12\n  KUBERNETES_IP_FABRIC_SUBNETS: 10.80.0.0/12|g' tf.yaml

# kubectl apply -f tf.yaml

# # --- New TF Install Process --- #
# sleep 300
# git clone https://github.com/Juniper/contrail-container-builder.git
# cd contrail-container-builder/kubernetes/manifests/
# bash resolve-manifest.sh contrail-standalone-kubernetes.yaml >> $HOME/tf.yaml
# cd $HOME
# kubectl apply -f tf.yaml

# --- Manually fixed issues with TF Install Process --- #
sudo mkdir -pm 777 /var/lib/contrail/kafka-logs
sed -i "s/{{ K8S_MASTER_IP }}/$K8S_MASTER_IP/g" tf.yaml
sed -i "s/{{ VROUTER_GATEWAY }}/$VROUTER_GATEWAY/g" tf.yaml
sed -i "s/{{ CONTRAIL_REPO }}/$TF_REPO/g" tf.yaml
sed -i "s/{{ CONTRAIL_RELEASE }}/$TF_RELEASE/g" tf.yaml
kubectl apply -f tf.yaml