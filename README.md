# patient-notes-api: containers, CI, GitOps and AWS infrastructure

A small Node.js REST API with a production-style delivery path on AWS:

**GitHub Actions** (test, build, scan, push to ECR) → **git commit of the new image tag** → **Argo CD** deploys it to **EKS**, with all infrastructure in **Terraform**.

The app is intentionally trivial (in-memory CRUD plus `/healthz` and `/readyz`). The interesting part is everything around it.

```
PR / push to main
  └─ lint + test ─► docker build ─► Trivy scan (gate) ─┬─ PR: stop (nothing pushed, no cloud credentials)
                                                       └─ main: OIDC → push :<sha> to ECR
                                                                 └─ commit new tag to k8s/app/kustomization.yaml
                                                                       └─ Argo CD syncs it to EKS (CI never touches the cluster)
```

## Layout

```
.
├── app/                    Express API, tests, ESLint
├── docker/                 Dockerfile + Dockerfile.dockerignore
├── .github/workflows/
│   ├── ci.yml              lint/test → build → Trivy → ECR → bump image tag in git
│   └── infra-checks.yml    terraform fmt/validate, kubeconform (PRs touching infra)
├── k8s/
│   ├── app/                the service: Deployment, Service, Ingress, NetworkPolicy, ExternalSecret…
│   └── platform/           cluster setup for EKS Auto Mode: NetworkPolicy controller, ALB IngressClass
├── argocd/
│   ├── root.yaml           applied once by hand (app-of-apps)
│   └── apps/               project, External Secrets Operator, platform, patient-notes-api
└── terraform/
    ├── bootstrap.sh        one-time state-bucket bootstrap for the shared stack
    ├── modules/            state-bucket, ecr, ci-iam-role (small, reusable)
    ├── shared/             state bucket · VPC · ECR · CI IAM role
    └── service/            EKS · Pod Identity IAM · Secrets Manager · ACM certificate
```

## Try the API locally

Requires Node.js 20 or newer. The API stores data in memory, so created items disappear when it restarts.

```bash
cd app
npm ci
npm run lint
npm test
npm start
```

In another terminal, check `http://localhost:8080/healthz`, or build and run the container from the repository root:

```bash
docker build -f docker/Dockerfile -t patient-notes-api:dev app/
docker run --rm -p 8080:8080 patient-notes-api:dev
```

The Docker build uses BuildKit features and requires Docker Buildx/BuildKit (included with Docker Desktop; on Linux, install the Buildx plugin).

### Why two Terraform stacks

| | `shared/` | `service/` |
|---|---|---|
| Owns | S3 state bucket, VPC, ECR, CI role (GitHub OIDC) | EKS cluster, External Secrets IAM role, Secrets Manager secret, ACM certificate |
| Changes | rarely; many services depend on it | with the service/cluster |
| Wiring | exposes outputs | reads shared outputs via `terraform_remote_state` |

Separate state files keep the blast radius of a service change away from the network and registry.

### Key design choices

- **EKS Auto Mode**: AWS runs nodes, CoreDNS, the load balancer controller and Pod Identity. No node groups or controller Helm charts to maintain. The **ALB is created from the Ingress**; Terraform only provides the ACM certificate.
- **GitOps**: Argo CD pulls from git, so CI needs no cluster credentials. Deploys are commits; rollback is `git revert` of the image-tag commit.
- **No long-lived credentials anywhere**: CI uses GitHub OIDC; the External Secrets controller uses EKS Pod Identity; the app has no AWS access at all.
- **Secrets**: real values live in AWS Secrets Manager (Terraform creates only the empty secret, so values never reach state or git). External Secrets Operator syncs them into a Kubernetes Secret.
- **Demo secret**: the API currently does not read `API_KEY`; it is included to demonstrate secret provisioning and Kubernetes injection.
- **Default-deny NetworkPolicy**: the pod accepts traffic only from the VPC on 8080 and may only talk to cluster DNS.

## First-time setup (in order)

Prerequisites: AWS credentials with admin rights for the first apply, Terraform ≥ 1.10, kubectl, a Route 53 hosted zone for the API hostname.

> **Cost warning:** this creates billable AWS resources, including an EKS cluster, NAT gateway(s), and an internet-facing load balancer. The default VPC uses one NAT gateway per Availability Zone; set `single_nat_gateway = true` in `terraform/shared/terraform.tfvars` to lower demo costs, with reduced availability.

**0. Point the manifests at your repo.**
```bash
grep -rl 'OWNER/REPO' argocd | xargs sed -i 's#OWNER/REPO#your-org/your-repo#'
```

**1. Shared stack** (creates the state bucket, then moves its own state into it):
```bash
cd terraform/shared
# Use terraform.tfvars for your development values. Create it if missing, with a
# globally unique state_bucket_name and github_repository = "OWNER/REPO".
cd .. && AWS_REGION=eu-west-1 ./bootstrap.sh
cd shared && terraform plan -out tfplan && terraform apply tfplan
```

**2. GitHub repository variables** (Settings → Secrets and variables → Actions → Variables):
`AWS_CI_ROLE_ARN` = output `ci_role_arn`; optionally `AWS_REGION` and `ECR_REPOSITORY` if not the defaults.
If `main` is branch-protected, allow `github-actions[bot]` to push to it, because CI commits the image tag there.

**3. First image.** Merge to `main`. CI pushes the image and commits its tag to `k8s/app/kustomization.yaml`.

**4. Service stack:**
```bash
cd terraform/service
cp backend-dev.hcl backend.hcl
cp dev.tfvars terraform.tfvars
# Edit terraform.tfvars: use your shared state bucket, API CIDR, domain, and hosted-zone ID.
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
```
Creating the cluster and validating the certificate takes ~15–20 minutes.

**5. Finish the config that depends on Terraform outputs** and commit it:
- `k8s/platform/platform.yaml`: set `certificateARNs` to output `acm_certificate_arn`.
- `k8s/app/service-ingress.yaml`: set the Ingress `host` to your `domain_name`.
- The External Secrets `SecretStore` defaults to `eu-west-1`; if you chose another AWS region, update `k8s/app/externalsecret.yaml` to match `aws_region`.
- Store the real secret value (never in git):
  ```bash
  aws secretsmanager put-secret-value --secret-id patient-notes-api/production/app \
    --secret-string '{"API_KEY":"<real value>"}'
  ```

**6. Install Argo CD once, then hand everything else to it:**
```bash
$(terraform output -raw configure_kubectl)
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml
kubectl apply -f ../../argocd/root.yaml
```
Argo CD now installs External Secrets, applies `k8s/platform`, then deploys the service (sync waves order these).

**7. Verify and add DNS.**
```bash
kubectl -n argocd get applications
kubectl -n patient-notes get pods,externalsecret,ingress
curl -fsS https://<domain_name>/readyz
```
Create a DNS record (alias/CNAME) from your domain to the ALB hostname shown on the Ingress.
Argo CD UI: `kubectl -n argocd port-forward svc/argocd-server 8080:443`; initial admin password is in secret `argocd-initial-admin-secret`.

## Day-to-day

- **Trigger CI**: open a PR to `main` (lint, test, build, scan; nothing is pushed) or merge to `main` (also pushes to ECR and updates the deployed tag). For pull requests, changes under `terraform/`, `k8s/` or `argocd/` run `infra-checks.yml`; app CI is skipped when a change only touches those paths.
- **Deploy**: merge. CI commits the new tag; Argo CD syncs automatically (self-heal and prune on).
- **Roll back**: `git revert` the `deploy: patient-notes-api <sha>` commit.
- **Apply the Kubernetes manifests manually** (debugging only; Argo CD will revert drift): `kubectl kustomize k8s/app | kubectl apply -f -`.
- **Terraform changes**: `terraform plan` / `apply` in `terraform/shared` or `terraform/service`, after `terraform init -backend-config=backend.hcl`.

## Migration question: importing a manually-created resource into Terraform

Goal: bring an existing resource (say, a hand-made S3 bucket or ECR repo) under Terraform without recreating it or interrupting traffic. Import only edits Terraform *state*; it never touches the real resource, so it causes no downtime by itself. The risk is a later `apply` that "fixes" drift by replacing or modifying the resource, which is why the steps end with a clean plan.

1. **Inventory and freeze**: record the resource's real configuration (console/CLI, or `terraform plan -generate-config-out`) and agree a short change freeze on it.
2. **Back up state**: the state bucket is versioned, so rollback is possible; take a manual copy too. Rehearse on a non-prod copy if one exists.
3. **Write the resource block** in the right stack/module to match reality (names, tags, policies, settings).
4. **Import declaratively** with an `import { to = ...; id = ... }` block (Terraform ≥ 1.5), which is reviewable in a PR. `terraform import <addr> <id>` is the imperative equivalent.
5. **Iterate on `terraform plan` until it shows no changes** (or only intended, additive ones like tags). Any `replace` or `destroy` is a stop sign: fix the config to match reality (force-new attributes such as names and subnets must match exactly).
6. **Add guardrails** before the first apply: `lifecycle { prevent_destroy = true }` and `ignore_changes` for attributes managed elsewhere.
7. **Apply** (state-only), re-run `plan` to confirm a no-op, remove the `import` block and merge. From then on Terraform is the only way it changes: restrict console write access and run a scheduled `terraform plan` to detect drift.

## Assumptions, trade-offs and gaps

**Validation limits.** Local checks can validate formatting, Terraform syntax, Kubernetes rendering, and the app tests, but they cannot prove that AWS resources will provision successfully. Validate the Terraform plan before applying it, and check `kubectl describe ingress` after deployment if the ALB does not become healthy; EKS Auto Mode supports only a subset of ALB annotations.

Trade-offs made on purpose:
- **One environment.** Manifests are flat (`k8s/app`), not base/overlays, and Terraform has no workspaces. Add `k8s/overlays/<env>` and a second `service/` state key when a second environment exists.
- **CI commits straight to `main`** to bump the image tag. Simple and auditable, but needs a branch-protection bypass for the bot; a PR-based bump (or Argo CD Image Updater) is the stricter alternative.
- **Argo CD is installed by hand, once**, to avoid Terraform managing in-cluster resources before the cluster exists. It does not manage itself (add an Application for it later), has no SSO/ingress (port-forward only), and the initial admin account should be disabled once SSO is set up.
- **Public EKS API endpoint**, restricted to `api_allowed_cidrs`. A private endpoint plus VPN/bastion is stricter.
- **NetworkPolicy values are coupled to Terraform**: VPC CIDR `10.0.0.0/16` and DNS `172.20.0.10` (pinned service CIDR). Change them together.
- **DNS is manual.** The ALB hostname is created by the Ingress, so the record to it is added by hand (ExternalDNS would automate it).
- **Secrets Manager uses the default AWS-managed KMS key**; a customer-managed key is the next step for stricter control. Secret rotation is not configured.
- **No autoscaling or observability.** Fixed 2 replicas + PodDisruptionBudget (Auto Mode scales nodes, not pods); add an HPA and a metrics/alerting stack (Prometheus/CloudWatch) before real traffic. Control-plane logs and VPC flow logs are enabled.
- **GitHub Actions are pinned to version tags, not commit SHAs**; pin SHAs with Dependabot for supply-chain hygiene. No image signing (cosign) or SBOM.
- **Trivy** gates on fixable HIGH/CRITICAL only (`ignore-unfixed`), with no exception file.
- **Cost**: one NAT gateway per AZ by default (set `single_nat_gateway = true` for non-prod). The state bucket keeps old versions 90 days.
- **Versions pinned at the time of writing**: Argo CD v3.5.2, External Secrets chart 2.11.0, EKS module `~> 21.0`, VPC module `~> 6.0`, AWS provider `~> 6.0`. Commit the `.terraform.lock.hcl` files after the first `init`.
