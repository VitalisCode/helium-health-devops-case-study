# patient-notes-api: containerise, CI, Kubernetes, Terraform

A small Node.js (Express) REST API onboarded to the platform: containerised, built and scanned in GitHub Actions, deployed to Kubernetes, with supporting AWS infrastructure defined in Terraform.

The app is intentionally trivial (in-memory CRUD plus `/healthz` and `/readyz`); the focus is the delivery path.

```
repo/
├── app/                  # Express API, tests, ESLint config
├── .github/workflows/    # ci.yml
├── docker/               # Dockerfile + Dockerfile.dockerignore
├── k8s/                  # Kubernetes manifests (kustomize)
├── terraform/            # root config, bootstrap/ (state bucket), modules/
└── README.md
```

## Flow at a glance

```
PR / push to main
   └─ lint + test ─► docker build ─► Trivy scan (gate) ─┬─ PR: stop here (nothing pushed)
                                                        └─ main: OIDC → ECR push (:<sha>, :main)
                                                                       └─ kubectl apply -k k8s/  (manual today)
```

## 1. Run the app locally

```bash
cd app
npm ci
npm run lint && npm test
npm start            # http://localhost:8080/healthz
```

## 2. Container image

```bash
docker build -f docker/Dockerfile -t patient-notes-api:dev app/
docker run --rm -p 8080:8080 patient-notes-api:dev
```

- Multi-stage: a `deps` stage installs production dependencies only; the runtime stage copies just those and `src/`.
- `node:22-alpine` base, runs as numeric non-root UID 1000, no shell tooling beyond what Alpine ships.
- `CMD ["node", ...]` (not `npm start`) so SIGTERM reaches the process; the app drains connections on shutdown.
- The ignore file is `docker/Dockerfile.dockerignore`. BuildKit looks for `<Dockerfile name>.dockerignore` next to the Dockerfile, which lets the Dockerfile live in `docker/` as in the suggested layout while the build context is `app/`.

## 3. How to trigger the CI pipeline

The workflow `.github/workflows/ci.yml` runs automatically on:

| Event | What runs |
|---|---|
| Pull request to `main` | lint, test, image build, Trivy scan. **Nothing is pushed** and no cloud credentials are issued. |
| Push/merge to `main` | all of the above, then push to ECR as `:<git-sha>` (immutable) and `:main` |

To trigger it: open a PR against `main`, or merge one. No manual step.

One-time setup for the push step:

1. Apply the Terraform in `terraform/` (section 5); it outputs `ci_role_arn`.
2. In GitHub, go to Settings → Secrets and variables → Actions → **Variables** and add:
   - `AWS_CI_ROLE_ARN` = the `ci_role_arn` output
   - `AWS_REGION` (default `eu-west-1`) and `ECR_REPOSITORY` (default `patient-notes-api`), if different.

There are **no AWS secrets in GitHub**. The job authenticates through GitHub's OIDC token and assumes the Terraform-created role, which is restricted to this repo's `main` branch and to pushing into one ECR repository.

The Trivy step fails the job on fixable HIGH/CRITICAL vulnerabilities, and runs *before* the push so a vulnerable image never reaches the registry. A second Trivy pass uploads SARIF to the GitHub Security tab.

## 4. How to apply the Kubernetes manifests

Prerequisites: a cluster with an NGINX ingress controller (namespace `ingress-nginx`), and cert-manager if you want the TLS annotation to work.

```bash
# 1. Point the manifests at the image CI pushed (registry URL = terraform output ecr_repository_url)
cd k8s
kustomize edit set image \
  ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com/patient-notes-api=<ecr_repository_url>:<git-sha>

# 2. Review, then apply
kubectl kustomize . | less
kubectl apply -k .

# 3. Verify
kubectl -n patient-notes rollout status deploy/patient-notes-api
kubectl -n patient-notes get pods,svc,ingress,networkpolicy
```

What is in `k8s/`:

- **Namespace** with the Pod Security `restricted` profile enforced, plus a ServiceAccount with token automount disabled.
- **Deployment**: 2 replicas, rolling update with `maxUnavailable: 0`, requests/limits, startup + liveness (`/healthz`) + readiness (`/readyz`) probes, read-only root filesystem, all capabilities dropped, seccomp `RuntimeDefault`, topology spread, `preStop` sleep for clean endpoint removal. A PodDisruptionBudget keeps at least 1 pod up during node drains.
- **Service** (ClusterIP) and **Ingress** (NGINX, TLS via cert-manager annotation, host `notes-api.example.com` is a placeholder).
- **NetworkPolicy**: default-deny for the namespace, then an allow-list: ingress only from the `ingress-nginx` namespace on port 8080; egress only to cluster DNS (kube-dns, port 53). The app has no other dependencies, so nothing else is open. Requires a CNI that enforces NetworkPolicy (Calico, Cilium, or the VPC CNI with network policy enabled).
- **ConfigMap** (non-sensitive config) and **Secret** (placeholders).

## 5. Terraform

Layout:

```
terraform/
├── bootstrap/          # one-time: creates the state bucket (local state)
├── modules/
│   ├── state-bucket/   # S3: versioning, encryption, public-access block, TLS-only policy
│   ├── ecr/            # ECR: immutable tags, scan on push, lifecycle policy
│   └── ci-iam-role/    # GitHub OIDC provider + least-privilege role
├── main.tf variables.tf outputs.tf versions.tf   # root config (uses ecr + ci-iam-role)
├── backend.hcl.example
└── terraform.tfvars.example
```

All three requested resources are covered, using three reusable modules, a remote S3 backend, and documented variables/outputs.

```bash
# A. Create the state bucket (once per account/environment)
cd terraform/bootstrap
terraform init
terraform apply -var state_bucket_name=<globally-unique-name>

# B. Configure the remote backend and apply the main stack
cd ..
cp backend.hcl.example backend.hcl            # fill in bucket + region
cp terraform.tfvars.example terraform.tfvars  # set github_repository = "owner/repo"
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```

Key design points:

- **Backend config is injected, not hardcoded** (`-backend-config`), because backend blocks cannot use variables and bucket names are account-specific.
- **State locking** uses S3-native lockfiles (`use_lockfile`, Terraform >= 1.10), so no DynamoDB table is needed.
- **CI role**: trust policy pins the OIDC `sub` claim to `repo:<owner>/<repo>:ref:refs/heads/main`, so PRs and other branches cannot assume it. Permissions are ECR push actions on one repository ARN, plus `ecr:GetAuthorizationToken` (which AWS only allows on `*`).
- **ECR**: tags are immutable (a SHA tag always means the same image); lifecycle policy expires untagged images after 7 days and keeps the most recent 30.

## 6. Migration question: importing a manually-created resource into Terraform

Goal: bring an existing resource (say, a hand-made S3 bucket or ECR repo) under Terraform management without recreating it or interrupting traffic. Import only edits Terraform *state*; it never touches the real resource, so it causes no downtime by itself. The risk is a later `apply` that "fixes" drift by replacing or modifying the resource, which is why the steps below end with a clean plan.

1. **Inventory and freeze**: record the resource's real configuration (console, CLI, or `terraform plan -generate-config-out`), and agree a short change freeze on it so it doesn't drift mid-migration.
2. **Back up state**: the S3 backend is versioned, so I can roll back; I'd also take a manual copy of the state file before starting. Run against a non-prod copy of the resource first if one exists.
3. **Write the resource block** in the right module to match reality as closely as possible (names, tags, policies, settings).
4. **Import declaratively** with an `import { to = ...; id = ... }` block (Terraform >= 1.5), which shows up in `terraform plan` and is reviewable in a PR. `terraform import <addr> <id>` is the imperative equivalent. For many resources, `-generate-config-out` produces a starting draft.
5. **Iterate on `terraform plan` until it shows no changes** (or only intentional, additive ones like tags). Any proposed `replace` or `destroy` is a stop sign: fix the config to match reality instead (e.g. force-new attributes such as names and subnets must match exactly).
6. **Add guardrails** before the first apply: `lifecycle { prevent_destroy = true }` and, if needed, `ignore_changes` for attributes managed elsewhere.
7. **Apply** the import (state-only), run `plan` again to confirm a clean no-op, then remove the `import` block and merge. Make Terraform the only way the resource is changed from here on (restrict console write access, add drift detection with a scheduled `terraform plan`).

## 7. Assumptions and trade-offs (shortcuts taken)

**Not verified here.** The sandbox this was built in has no Docker daemon and cannot download the Terraform binary. What *was* run: `npm run lint` and `npm test` (5 tests passing), and syntax parsing of every YAML and HCL file. What was **not** run: `docker build`, `terraform validate/plan`, `kubectl apply`, and the GitHub Actions workflow itself. Please run those before relying on any of it.

Shortcuts and assumptions:

- **App**: in-memory store, no auth, no structured logging or metrics. It exists only to be deployed.
- **Secrets**: `k8s/secret.yaml` holds placeholders so the shape is visible. Intended approach: store real values in AWS Secrets Manager and sync them with External Secrets Operator (or Secrets Store CSI) using IRSA/Pod Identity; the Secret manifest would then be deleted from the repo. Never commit real values.
- **Deploy is manual** (`kubectl apply -k`). CI stops at "image in registry". A real setup would use GitOps (Argo CD/Flux) watching this repo, with CI opening a PR that bumps the image tag, which also avoids giving CI cluster credentials.
- **GitHub Actions are pinned to version tags**, not commit SHAs. Pinning to SHAs (with Dependabot to update them) is better supply-chain hygiene.
- **Image tags**: `:<sha>` is the deploy reference; `:main` is a moving convenience tag. Image signing (cosign) and SBOM generation are not included.
- **Trivy gate** ignores unfixed vulnerabilities (`ignore-unfixed`) to avoid blocking on issues nobody can patch yet; there is no `.trivyignore` or exception process.
- **Single environment/region**, single AWS account. Real use would add per-environment state keys or workspaces, and separate accounts for prod.
- **State bucket**: uses SSE-S3 by default (KMS key is an optional input); `bootstrap/` keeps its own local state, which should be backed up or migrated into the bucket after creation.
- **Terraform provider pinned to `~> 5.80`**; a `.terraform.lock.hcl` should be generated and committed on first `init`.
- **Ingress** assumes NGINX + cert-manager with a `letsencrypt-prod` ClusterIssuer; the host is a placeholder. No HPA is defined (replica count is fixed at 2).
- **Observability** (metrics, tracing, alerting) is out of scope; the probes and `/healthz` endpoint are the only hooks.
