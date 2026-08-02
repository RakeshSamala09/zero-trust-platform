# Samala CI → Ansible Deploy Flow

## Flow
```
push to main (apps/samala-backend/**)
    ↓
sonarqube ─┐
            ├─> build-scan-push (build image, Trivy scan, push :SHA and :latest to ECR)
owasp     ─┘        ↓
                  deploy (Ansible playbook, pulls the exact :SHA tag, kubectl set image + rollout)
```
Same for `samala-frontend-ci.yml`. Each pipeline only touches its own deployment — pushing a
backend change never redeploys the frontend and vice versa.

## New GitHub secrets needed (in addition to the ones from before)

| Secret                   | Value                                                                 |
|----------------------------|--------------------------------------------------------------------|
| `ANSIBLE_SSH_PRIVATE_KEY`   | Contents of your `terraform/zero-trust-key.pem` (the master node's SSH key) |
| `ANSIBLE_INVENTORY`          | Contents of your `ansible/inventory.ini` (master/worker IPs + groups)        |

To get these onto your clipboard for pasting into GitHub Settings → Secrets:
```bash
cat ~/zero-trust-platform/terraform/zero-trust-key.pem
cat ~/zero-trust-platform/ansible/inventory.ini
```
Paste each file's full contents as the secret value (multi-line is fine, GitHub secrets support it).

## Files to add to your repo
```bash
cp ansible/deploy-samala.yml ~/zero-trust-platform/ansible/
cp .github/workflows/samala-backend-ci.yml  ~/zero-trust-platform/.github/workflows/
cp .github/workflows/samala-frontend-ci.yml ~/zero-trust-platform/.github/workflows/
```

## First-time only — deploy the database manually
The CI pipelines only handle backend/frontend (their own image). The database needs to exist
before either app can start successfully. Run this once from wherever you normally run `playbook.yml`:
```bash
cd ~/zero-trust-platform/ansible
ansible-playbook -i inventory.ini deploy-samala.yml --tags database
```

## After that — just git push
```bash
git add apps/samala-backend
git commit -m "some backend change"
git push origin main
```
Watch the Actions tab: sonarqube + owasp run in parallel → build-scan-push → deploy.
Once "deploy" goes green, `kubectl rollout status` inside the playbook confirms the new pods are
actually up and healthy — not just that `kubectl apply` was accepted.

## Why kubectl set image instead of ArgoCD sync
Your `sample-app` uses the GitOps pattern (ArgoCD watches git, git is the source of truth for the
image tag). For samala right now, `deploy-samala.yml` uses `kubectl set image` directly — this is
simpler and matches what you asked for (CI pushes image → Ansible pulls tag → applies), but it means
the image tag in `apps/samala-backend/k8s/deployment.yml` in git stays stale (still says
`:latest`). That's fine for now, but if you later want git to always reflect what's actually
running (full GitOps, matching your sample-app), the deploy job would instead commit the new tag
into `deployment.yml` and let ArgoCD auto-sync — happy to wire that up when you're ready for it.

## Sanity checks before first run
- `ecr-pull-secret` gets refreshed on every deploy (tokens expire ~12h) — no action needed from you.
- Deployment's container `name:` must match what `kubectl set image` targets — already verified:
  `samala-backend` deployment has container `name: backend`, `samala-frontend` has `name: frontend`.
- If the SSH connection times out from GitHub's runners, check your EC2 security group allows
  inbound SSH (port 22) from GitHub Actions IP ranges, or from `0.0.0.0/0` if you're OK with that
  (mitigated by needing the private key anyway).
