# Sample App — Zero Trust Platform

Minimal Flask app, containerized with security best practices (non-root,
read-only filesystem, dropped capabilities), deployed via ArgoCD GitOps.

## 1. Push this to GitHub

```bash
git init
git add .
git commit -m "Add sample app + K8s manifests"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/zero-trust-platform.git
git push -u origin main
```

(If you already have a repo from the Terraform files, just add this
`sample-app/` folder into that same repo instead of creating a new one —
one repo holding both infra and app manifests tells a cleaner story.)

## 2. Build and push the Docker image

You'll need a Docker Hub account (free) or use Amazon ECR (already has IAM
permissions set up from Terraform).

**Docker Hub (simplest):**
```bash
docker build -t YOUR_DOCKERHUB_USERNAME/zero-trust-sample-app:latest .
docker login
docker push YOUR_DOCKERHUB_USERNAME/zero-trust-sample-app:latest
```

**Or Amazon ECR (matches the IAM role we already provisioned):**
```bash
aws ecr create-repository --repository-name zero-trust-sample-app --region ap-south-1

aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com

docker build -t <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/zero-trust-sample-app:latest .
docker push <your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/zero-trust-sample-app:latest
```

Then update the `image:` field in `k8s/deployment.yaml` to match whichever
registry you used, and commit + push that change.

## 3. Update the ArgoCD Application manifest

Edit `argocd-application.yaml` — replace `YOUR_GITHUB_USERNAME` with your
actual GitHub username, and confirm the `path` matches where this folder
sits in your repo (default assumes `sample-app/k8s`).

## 4. Apply the Application to ArgoCD

On the master (where kubectl is already configured):
```bash
kubectl apply -f argocd-application.yaml
```

Or via ArgoCD CLI instead:
```bash
argocd app create sample-app \
  --repo https://github.com/YOUR_GITHUB_USERNAME/zero-trust-platform.git \
  --path sample-app/k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated
```

## 5. Sync and verify

```bash
argocd app sync sample-app
kubectl get pods
kubectl get svc sample-app
```

Access it:
```
http://<any_node_public_ip>:30500
```

You should see JSON: `{"message": "Hello from Zero Trust Platform!", ...}`

## 6. Prove GitOps works

Change something in `k8s/deployment.yaml` (e.g. `replicas: 3`), commit,
push. Within ~3 minutes (default ArgoCD poll interval) or instantly if you
run `argocd app sync sample-app`, the cluster updates itself — no manual
`kubectl apply` needed. Screenshot this for your resume/LinkedIn proof.
