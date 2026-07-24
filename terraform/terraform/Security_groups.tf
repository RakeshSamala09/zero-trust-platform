# Security group for the K8s master node
resource "aws_security_group" "k8s_master" {
  name        = "${var.project_name}-master-sg"
  description = "Security group for kubeadm control plane node"
  vpc_id      = aws_vpc.main.id

  # SSH — only from your IP, never 0.0.0.0/0
  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }  
    
    # Kubernetes API server — only from your IP
  ingress {
    description = "K8s API server from admin IP only"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # Kubernetes API server — from worker nodes inside the VPC (needed for kubeadm join)
  ingress {
    description = "K8s API server from workers inside VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  

  

  # etcd — only from within the VPC (worker nodes never need this, only master-to-master in HA setups)
  ingress {
    description = "etcd internal only"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # kubelet API — internal VPC only
  ingress {
    description = "kubelet API internal"
    from_port   = 10250
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Calico BGP + VXLAN — internal only
  ingress {
    description = "Calico networking internal"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "Calico VXLAN internal"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort range — from your IP only, for testing services before you add ingress
  ingress {
    description = "NodePort range from admin IP"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # ArgoCD / Jenkins UI access if exposed via NodePort — same rule as above covers it

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-master-sg"
  }
}

# Security group for worker nodes
resource "aws_security_group" "k8s_worker" {
  name        = "${var.project_name}-worker-sg"
  description = "Security group for kubeadm worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "kubelet API internal"
    from_port   = 10250
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NodePort range internal + admin IP"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NodePort range from admin IP for direct testing"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Calico networking internal"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "Calico VXLAN internal"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-worker-sg"
  }
}
