data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Optional: Terraform-managed key pair if you didn't already create one.
# Set ssh_public_key_path to use this; otherwise it's skipped and
# key_pair_name (an existing pair) is used instead.
resource "aws_key_pair" "generated" {
  count      = var.ssh_public_key_path != "" ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = file(var.ssh_public_key_path)
}

locals {
  key_name = var.ssh_public_key_path != "" ? aws_key_pair.generated[0].key_name : var.key_pair_name

  # Installs containerd + kubeadm/kubelet/kubectl on every node.
  # Master vs worker role is decided later manually (kubeadm init vs kubeadm join)
  # so you keep full control/visibility over cluster bootstrap for the resume writeup.
  common_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Disable swap (required by kubelet)
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab

    # Kernel modules + sysctl for K8s networking
    cat <<MODULES | tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    MODULES
    modprobe overlay
    modprobe br_netfilter

    cat <<SYSCTL | tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    SYSCTL
    sysctl --system

    # Install containerd
    apt-get update
    apt-get install -y ca-certificates curl gnupg apt-transport-https

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y containerd.io

    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd

    # Install kubeadm, kubelet, kubectl
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    echo "Bootstrap complete. Node ready for 'kubeadm init' or 'kubeadm join'." > /var/log/bootstrap-done.log
  EOF
}

resource "aws_instance" "k8s_master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k8s_master.id]
  key_name                    = local.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_node_profile.name
  associate_public_ip_address = true
  user_data                   = local.common_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-master"
    Role = "control-plane"
  }
}

resource "aws_instance" "k8s_worker" {
  count                        = 2
  ami                          = data.aws_ami.ubuntu.id
  instance_type                = var.instance_type
  subnet_id                    = aws_subnet.public.id
  vpc_security_group_ids       = [aws_security_group.k8s_worker.id]
  key_name                     = local.key_name
  iam_instance_profile         = aws_iam_instance_profile.ec2_node_profile.name
  associate_public_ip_address  = true
  user_data                    = local.common_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "worker"
  }
}
# Elastic IP — keeps the master's public IP fixed even if the instance
# stops/starts. Free while attached to a running instance.
resource "aws_eip" "master" {
  instance = aws_instance.k8s_master.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-master-eip"
  }
}