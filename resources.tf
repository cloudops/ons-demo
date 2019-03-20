# Setup the provider
provider "cloudca" {
	api_key = "${var.api_key}"
}

# Require that `terraform workspace` is used
# Exit if the `default` workspace is used
resource "null_resource" "validate_workspace" {
  provisioner "local-exec" {
    command = <<EOF
      set -e
      if [ \"${terraform.workspace}\" == \"default\" ]; then
        echo "ERROR: Must not use the 'default' terraform workspace.  Use 'terraform workspace new <workspace_name>' instead."
        exit 1
      fi
      exit 0
    EOF
  }
}

# Unique ID for the environment (since they must be unique)
# We are using this so each demo attendee will get a different environment name
resource "random_id" "environment" {
  depends_on = ["null_resource.validate_workspace"]

  # set to '2' because we don't need it to be too long
  byte_length = 2
}

# Build the k8s token
resource "random_string" "token" {
  length  = 23
  upper   = false
  special = false
}
locals {
  token = "${replace(random_string.token.result, "/^(.{6})(.{1})(.{16})$/", "$1.$3")}"
}

# Setup an ssh key
resource "tls_private_key" "ssh_key" {
  depends_on = ["null_resource.validate_workspace"]

  algorithm = "RSA"
  rsa_bits  = "4096"
}
resource "local_file" "ssh_key_private" {
  depends_on = ["null_resource.validate_workspace"]

  content  = "${tls_private_key.ssh_key.private_key_pem}"
  filename = "./terraform.tfstate.d/${terraform.workspace}/id_rsa"

  provisioner "local-exec" {
    command = "chmod 400 ./terraform.tfstate.d/${terraform.workspace}/id_rsa"
  }
}
resource "local_file" "ssh_key_public" {
  depends_on = ["null_resource.validate_workspace"]

  content  = "${tls_private_key.ssh_key.public_key_openssh}"
  filename = "./terraform.tfstate.d/${terraform.workspace}/id_rsa.pub"
}

# Environment for the demo
resource "cloudca_environment" "demo_env" {
  name = "ons-demo-env-${random_id.environment.hex}"
  description = "'${terraform.workspace}'"
  service_code = "${var.service_name}"
  organization_code = "${var.organization}"
  admin_role = ["${var.admin_role}"]
}

# VPC for the demo
resource "cloudca_vpc" "demo_vpc" {
  name = "demo-vpc"
  description = "VPC for the demo"
  environment_id = "${cloudca_environment.demo_env.id}"
  vpc_offering = "Default VPC offering"
  zone = "${var.zone}"
}

# Network for the demo
resource "cloudca_network" "demo_network" {
  name = "demo-network"
  description = "Network for the demo"
  environment_id = "${cloudca_environment.demo_env.id}"
  vpc_id = "${cloudca_vpc.demo_vpc.id}"
  network_offering = "${var.network_offering}"
  network_acl = "default_allow"
}

# Master instance for the demo
resource "cloudca_instance" "master_instance" {
  name = "k8s-master"
  environment_id = "${cloudca_environment.demo_env.id}"
  network_id = "${cloudca_network.demo_network.id}"
  template = "${var.template}"
  compute_offering = "${var.compute_offering}"
  cpu_count = "${var.master_vcpu_count}"
  memory_in_mb = "${var.master_ram_in_mb}"
  root_volume_size_in_gb = "${var.master_root_volume_size_in_gb}"
  user_data = "${data.template_file.vm_config.rendered}"
}

resource "cloudca_volume" "k8s_data_volume" {
    environment_id = "${cloudca_environment.demo_env.id}"
    name = "K8S PV Data Volume"
    disk_offering = "Performance, No QoS"
    size_in_gb = 10
    instance_id = "${cloudca_instance.worker_instance.id}"
}

# Worker instance for the demo
resource "cloudca_instance" "worker_instance" {
  name = "k8s-worker"
  environment_id = "${cloudca_environment.demo_env.id}"
  network_id = "${cloudca_network.demo_network.id}"
  template = "${var.template}"
  compute_offering = "${var.compute_offering}"
  cpu_count = "${var.worker_vcpu_count}"
  memory_in_mb = "${var.worker_ram_in_mb}"
  root_volume_size_in_gb = "${var.worker_root_volume_size_in_gb}"
  user_data = "${data.template_file.vm_config.rendered}"
}

# The application install details defined in 'cloudinit'
data "template_file" "vm_config" {
  template = "${file("templates/vm_config.tpl")}"

  vars {
    public_key = "${replace(tls_private_key.ssh_key.public_key_openssh, "\n", "")}"
    username   = "${var.username}"
  }
}

# The public IP for the application
resource "cloudca_public_ip" "master_public_ip" {
  environment_id = "${cloudca_environment.demo_env.id}"
  vpc_id = "${cloudca_vpc.demo_vpc.id}"
}
resource "cloudca_public_ip" "worker_public_ip" {
  environment_id = "${cloudca_environment.demo_env.id}"
  vpc_id = "${cloudca_vpc.demo_vpc.id}"
}

# The PF rule to map the public port with the private port (ssh)
resource "cloudca_port_forwarding_rule" "master_ssh_pfr" {
  environment_id = "${cloudca_environment.demo_env.id}"
  public_ip_id = "${cloudca_public_ip.master_public_ip.id}"
  private_ip_id = "${cloudca_instance.master_instance.private_ip_id}"
  public_port_start = "22"
  private_port_start = "22"
  protocol = "TCP"
}
output "master =>" {
  value = "ssh ${var.username}@${cloudca_public_ip.master_public_ip.ip_address} -i ./terraform.tfstate.d/${terraform.workspace}/id_rsa"
}

resource "cloudca_port_forwarding_rule" "worker_ssh_pfr" {
  environment_id = "${cloudca_environment.demo_env.id}"
  public_ip_id = "${cloudca_public_ip.worker_public_ip.id}"
  private_ip_id = "${cloudca_instance.worker_instance.private_ip_id}"
  public_port_start = "22"
  private_port_start = "22"
  protocol = "TCP"
}
output "worker =>" {
  value = "ssh ${var.username}@${cloudca_public_ip.worker_public_ip.ip_address} -i ./terraform.tfstate.d/${terraform.workspace}/id_rsa"
}

# When instances change, setup additional details for the VM
resource "null_resource" "master_instance_setup" {
  # when an instance changes
  triggers {
    master = "${cloudca_instance.master_instance.id}"
  }

  # push the private key to the instance
  provisioner "file" {
    content     = "${tls_private_key.ssh_key.private_key_pem}"
    destination = "/home/${var.username}/.ssh/id_rsa"
  }

  # lock down the private ssh key
  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/${var.username}/.ssh/id_rsa"
    ]
  }

    # copy the TF config yaml in place
  provisioner "file" {
    source      = "templates/tf.yaml"
    destination = "/home/${var.username}/tf.yaml"
  }
  
  # copy the bash script in place
  provisioner "file" {
    source      = "templates/k8s_master.sh"
    destination = "/home/${var.username}/k8s_master.sh"
  }

  # make the script executable
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.username}/k8s_master.sh",
      "./k8s_master.sh ${cloudca_instance.master_instance.private_ip} ${join(".", slice(split(".", cloudca_instance.master_instance.private_ip), 0, 3))}.1 ${var.tf_release} '${local.token}'"
    ]
  }

  # the ssh connection details for this null resource
  connection {
    type        = "ssh"
    host        = "${cloudca_public_ip.master_public_ip.ip_address}"
    user        = "${var.username}"
    private_key = "${tls_private_key.ssh_key.private_key_pem}"
    port        = "22"
  }
}

resource "null_resource" "worker_instance_setup" {
  depends_on = ["null_resource.master_instance_setup", "cloudca_volume.k8s_data_volume"]

  # when an instance changes
  triggers {
    worker = "${cloudca_instance.worker_instance.id}"
  }

  # push the private key to the instance
  provisioner "file" {
    content     = "${tls_private_key.ssh_key.private_key_pem}"
    destination = "/home/${var.username}/.ssh/id_rsa"
  }

  # lock down the private ssh key
  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/${var.username}/.ssh/id_rsa"
    ]
  }

  # copy the bash script in place
  provisioner "file" {
    source      = "templates/k8s_worker.sh"
    destination = "/home/${var.username}/k8s_worker.sh"
  }

  # - partition, make fs and mount the data drive (for consul)
  # - make the k8s_worker script executable and run it
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir /data",
      "sudo mkfs.ext4 /dev/xvdb",
      "echo '/dev/xvdb    /data    ext4    defaults    0 2' | sudo tee -a /etc/fstab",
      "sudo mount -a",
      "chmod +x /home/${var.username}/k8s_worker.sh",
      "./k8s_worker.sh ${cloudca_instance.master_instance.private_ip} '${local.token}'"
    ]
  }

  # the ssh connection details for this null resource
  connection {
    type        = "ssh"
    host        = "${cloudca_public_ip.worker_public_ip.ip_address}"
    user        = "${var.username}"
    private_key = "${tls_private_key.ssh_key.private_key_pem}"
    port        = "22"
  }
}

# Finish the install of charts, etc...
resource "null_resource" "master_finalize_setup" {
  depends_on = ["null_resource.worker_instance_setup"]

  # when an instance changes
  triggers {
    master = "${cloudca_instance.master_instance.id}"
  }

  # copy the files in place
  provisioner "file" {
    source      = "templates/local_storage_pv.yaml"
    destination = "/home/${var.username}/local_storage_pv.yaml"
  }

  # copy the files in place
  provisioner "file" {
    source      = "templates/helm_consul_values.yaml"
    destination = "/home/${var.username}/helm_consul_values.yaml"
  }

  # Setup a Local Storage PV, Install Helm, Init Helm, Get and Install Consul
  provisioner "remote-exec" {
    inline = [
      "kubectl create -f local_storage_pv.yaml",
      "curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash",
      "kubectl create serviceaccount --namespace kube-system tiller",
      "kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller",
      "helm init --service-account tiller --history-max 200",
      "git clone https://github.com/hashicorp/consul-helm.git",
      "cd consul-helm",
      "git checkout v0.6.0",
      "sleep 5",
      "while [ \"$(kubectl get pods -l name=tiller -n kube-system -o 'jsonpath={.items[0].status.conditions[?(@.type==\"Ready\")].status}')\" != 'True' ]; do echo 'waiting for tiller...'; sleep 2; done",
      "helm install ./ -f /home/${var.username}/helm_consul_values.yaml"
    ]
  }

  # the ssh connection details for this null resource
  connection {
    type        = "ssh"
    host        = "${cloudca_public_ip.master_public_ip.ip_address}"
    user        = "${var.username}"
    private_key = "${tls_private_key.ssh_key.private_key_pem}"
    port        = "22"
  }
}
