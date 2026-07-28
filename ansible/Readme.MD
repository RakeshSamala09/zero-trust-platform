🔐 Built a Zero Trust Kubernetes platform from scratch on AWS — fully automated, end to end

Over the past few sessions, I designed and deployed a self-managed Kubernetes platform (kubeadm on EC2) with a complete zero-trust + GitOps stack:

🏗️ Terraform — VPC, IAM with a self-hosted OIDC provider for pod identity, EC2 nodes, fully destroyable infra (nothing left running, nothing left billing)

☸️ kubeadm + Calico — self-managed control plane and CNI, including debugging a real cross-node networking failure caused by a missing IP-in-IP protocol rule in AWS security groups

🔄 ArgoCD — 100% GitOps; zero manual kubectl apply for application deployments

🚀 GitHub Actions → Amazon ECR — CI pipeline builds and pushes container images automatically on every commit

🔐 Istio service mesh — strict mTLS enforced cluster-wide; every pod-to-pod connection is encrypted and mutually authenticated by default

🛡️ OPA Gatekeeper — wrote a custom Rego policy to block privileged containers at admission time, then proved it: deployed a deliberately non-compliant pod and watched Kubernetes reject it outright —
admission webhook "validation.gatekeeper.sh" denied the request: Privileged containers are not allowed

The real learning wasn't the happy path — it was the debugging. Traced a Redis connection timeout back to memory-starved nodes. Diagnosed a Calico cross-node routing failure through iptables NAT chains. Closed the gap on self-managed clusters' ECR authentication (something EKS handles automatically, kubeadm doesn't). Every one of these taught me more than the install steps ever could.

Next up: extending this into observability (Prometheus/Grafana), centralized logging, and scaling toward a multi-service architecture — all still fully Terraform-provisioned and GitOps-managed.

Repo + architecture diagram in comments 👇

#Kubernetes #ZeroTrust #Terraform #DevOps #CloudEngineering #GitOps #AWS #PlatformEngineering



Run this after terraform apply has created fresh EC2 instances, and instead of manually SSHing into each node.

Prerequisites
bash
pip install ansible --break-system-packages
Setup
Get your fresh instance IPs:
bash
   cd ../terraform
   terraform output master_public_ip
   terraform output worker_public_ips
Copy the inventory template and fill in real IPs:
bash
   cd ../ansible
   cp inventory.ini.example inventory.ini
Edit inventory.ini — replace REPLACE_WITH_MASTER_IP and the two worker placeholders with the actual IPs from step 1.

Confirm ansible.cfg points to the right private key path (../terraform/zero-trust-key.pem by default — adjust if yours lives elsewhere).
Update vars.yml if your AWS account ID, region, or GitHub repo URL differ from the defaults already filled in.
Run it
bash
ansible-playbook playbook.yml
This takes roughly 10-15 minutes end to end (Istio download/install is the slowest step). It's idempotent where practical — re-running it on an already-bootstrapped cluster should skip most steps rather than erroring, though this hasn't been stress-tested against every edge case yet.

What it does, in order
Waits for the EC2 user_data bootstrap script to finish
Runs kubeadm init on the master, sets up kubeconfig
Installs Calico CNI
Generates a fresh join token and joins both workers
Waits for all nodes to report Ready
Installs ArgoCD, exposes it via NodePort, prints the admin password + URL
Clones the app repo, creates an ECR pull secret, deploys the sample app via the ArgoCD Application manifest
Installs Istio (demo profile), enables sidecar injection on default, applies strict mTLS cluster-wide
Installs Gatekeeper, applies the custom policy blocking privileged containers
After running
Get your ArgoCD URL and password from the playbook's output (shown as a debug message during the ArgoCD play), or fetch them again anytime with:

bash
ansible master -m command -a "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'" -e "ansible_python_interpreter=/usr/bin/python3"
Known limitations (honest, for your own notes)
The ECR pull secret token expires in ~12 hours — re-run just that task block, or the whole playbook, to refresh it if pods start failing to pull images after a long-running session.
The kubeadm join token generated fresh each run means old tokens don't get cleaned up automatically — harmless, but worth knowing.
Istio gateways (ingress/egress) aren't explicitly removed here — if you're on a memory-constrained instance size again, you may want to add a task to delete them, same as we did manually before.
This playbook assumes a fresh cluster each time (paired with terraform destroy / apply cycles) — it's not been tested for upgrading an existing running cluster in place.
