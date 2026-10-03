# Rapyd Sentinel – Split Architecture PoC

Two isolated VPCs, one EKS cluster in each, private connectivity through VPC peering, and a
GitHub Actions pipeline that builds everything and proves it works end to end. Region:
`eu-west-2`.

```
                            Internet
                               │
                      ┌────────▼────────┐
                      │   Public NLB    │  internet-facing
                      └────────┬────────┘
   ┌───────────────────────────▼────────────────┐      ┌────────────────────────────────────────┐
   │ vpc-chacon-gateway          10.0.0.0/16    │      │ vpc-chacon-backend         10.1.0.0/16 │
   │ eks-chacon-gateway   (nodes in private)    │      │ eks-chacon-backend  (nodes in private) │
   │                                            │      │                                        │
   │   nginx reverse proxy ─────────────────────┼─VPC──┼─► internal NLB ─► backend pods         │
   │                                            │ peer │     "Hello from backend"               │
   │   NAT GW (public subnet)                   │      │   NAT GW (public subnet)               │
   └────────────────────────────────────────────┘      └────────────────────────────────────────┘
```

Resource names carry a `chacon` infix because the challenge account is shared and the
obvious names are already taken several times over.

## Repository layout

```
terraform/
  main.tf, variables.tf, outputs.tf, versions.tf   # root module: wires the modules together
  modules/
    networking/   # VPC, 2 private + 2 public subnets (2 AZs), IGW, NAT GW, route tables
    eks/          # IAM roles (eks- prefix), EKS cluster, node group, CI access entry
    peering/      # VPC peering, routes in both directions, backend security group rule
k8s/
  backend/        # namespace, nginx "Hello from backend", internal NLB Service
  gateway/        # namespace, nginx reverse proxy, public NLB Service
.github/workflows/
  deploy.yml      # validate -> lint -> plan -> apply -> deploy -> end-to-end test
  destroy.yml     # manual teardown
  oidc-debug.yml  # manual; decodes the OIDC token claims and calls STS directly
```

## How to clone and run

Terraform is **never** applied from a laptop; the pipeline does it.

1. Push this project to a GitHub repository's `main` branch.
2. Create an IAM role that trusts GitHub's OIDC provider for the repository and add its ARN
   as the repository secret `AWS_ROLE_ARN`. The trust policy has to match the `sub` claim the
   repository actually issues, which is often not the documented shape — see
   [Account constraints](#account-constraints-encountered).
3. Create an S3 bucket for Terraform state and add its name as the repository variable
   `TF_STATE_BUCKET`.
4. Push to `main`. The `deploy` workflow runs automatically. Pushes to other branches run
   validation, lint and `terraform plan` only.
5. Open the run summary: it prints the public URL and the response, which should be
   `Hello from backend`.

Static keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) remain as a fallback and are used
automatically when `AWS_ROLE_ARN` is absent. The delivered configuration authenticates purely
through OIDC; no long-lived credentials exist in the repository.

To tear everything down, run the `destroy` workflow manually.

## Networking

| | vpc-chacon-gateway | vpc-chacon-backend |
|---|---|---|
| CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| Private subnets (nodes, pods) | 2 × /20 in 2 AZs | 2 × /20 in 2 AZs |
| Public subnets | 2 × /24, used only by the NAT Gateway and the public NLB | 2 × /24, used only by the NAT Gateway |
| Outbound | NAT Gateway | NAT Gateway |
| EC2 instances with public IPs | none | none |

The gateway VPC requests the peering and the backend VPC accepts it, auto-accepted because
both live in the same account and region. Each VPC routes the other's CIDR through the
peering connection in both its private and public route tables, so return traffic always has
a path. The CIDRs do not overlap, which peering requires.

Access to the backend is restricted at two layers. The EKS-managed cluster security group of
the backend nodes gets one extra ingress rule for TCP 30000-32767 — the NodePort range the
NLB uses — accepting only the gateway VPC CIDR. The Kubernetes Service additionally sets
`loadBalancerSourceRanges` to the same CIDR. Nothing else from outside the backend VPC is
allowed in.

## How the proxy reaches the backend

The pipeline creates the backend Service as `type: LoadBalancer` with the annotation for an
**internal** NLB, which AWS places in the private subnets of `vpc-chacon-backend`. It then
reads that NLB's DNS name and renders it into the gateway's NGINX config as
`proxy_pass http://<internal-nlb-dns>`.

That hostname resolves to private `10.1.x.x` addresses. From a gateway pod the traffic path
is: node → route for `10.1.0.0/16` via the peering connection → internal NLB → backend node
NodePort, allowed by the security group rule → backend pod. Clients on the internet only ever
reach the gateway's public NLB, which forwards to the NGINX pods.

## CI/CD pipeline overview

`deploy.yml` runs on every push and can be dispatched manually.

The **validate** job runs `terraform fmt -check`, `terraform validate`, `tflint`, and offline
schema validation of the Kubernetes manifests with `kubeconform`.

The **deploy** job plans on every branch but applies and deploys only on `main`. It
authenticates to AWS, runs `terraform init / plan / apply`, builds kubeconfigs for both
clusters and waits for nodes. It then applies the backend with a server-side dry run first,
waits for the internal NLB, renders that hostname into the gateway manifests, applies the
gateway the same way, and waits for the public NLB. Two tests close it out: an **end-to-end
test** that curls the public URL until it returns `Hello from backend`, and a **negative
test** asserting the backend's internal NLB is *not* reachable from the runner.

A second run against existing infrastructure reports `0 added, 0 changed, 0 destroyed`, which
is the check that the configuration actually describes what is deployed.

## Account constraints encountered

The challenge account is shared and heavily scoped. Four constraints shaped decisions that
would otherwise look arbitrary in this repository.

**The GitHub OIDC subject claim carries immutable numeric IDs.** The tokens this repository
issues have a `sub` of
`repo:dschacon288@31111885/sentinel-split-devops-challenge@1398831308:ref:refs/heads/main`,
not the documented `repo:owner/name:ref:...` shape. A trust policy written against the plain
form never matches, and the failure surfaces only as
`Not authorized to perform sts:AssumeRoleWithWebIdentity`, which reads like a permissions
problem rather than a string mismatch. I diagnosed it with `oidc-debug.yml`, which decodes the
token payload and calls `sts:AssumeRoleWithWebIdentity` directly — the raw CLI error is more
specific than the one the action reports. The trust policy pins both IDs rather than
wildcarding them: immutable identifiers are the entire point of the feature, so renaming or
recreating the repository should break the binding rather than silently keep it.

**`iam:UpdateAssumeRolePolicy` is denied.** A trust policy cannot be corrected in place, so
fixing one means creating a replacement role. That is why the pipeline authenticates as
`sentinel-chacon-gha-v2` rather than the original `sentinel-chacon-gha`, which remains in the
account because `iam:DeleteRole` is unavailable too.

**`iam:TagRole` is denied.** The provider originally carried a `default_tags` block, which
made every `aws_iam_role` creation fail. I dropped it rather than work around it per-resource.
The tags that matter functionally — the `kubernetes.io/role/elb` and
`kubernetes.io/cluster/*` tags EKS uses for subnet discovery — are set explicitly in the
networking module and were never affected.

**The account is shared with other candidates.** Resource names carry a `chacon` infix to
avoid collisions; names like `eks-gateway-cluster-role` already exist.

## EKS authentication for the CI role

`bootstrap_cluster_creator_admin_permissions` grants cluster-admin only to the principal that
created the cluster. Once the pipeline moved from static keys to OIDC it authenticated as a
different principal, and `kubectl` failed with
`the server has asked for the client to provide credentials` — AWS authentication succeeded,
but Kubernetes RBAC had no binding for the role.

The `eks` module therefore creates an `aws_eks_access_entry` plus an
`AmazonEKSClusterAdminPolicy` association for the CI principal, injected as
`TF_VAR_ci_principal_arn` from the `AWS_ROLE_ARN` secret. Both resources sit behind a `count`
guard, so the module still works unmodified when no CI role is configured and the cluster
creator remains the only admin.

## Trade-offs and limitations

**Terraform state** lives in S3 with versioning and encryption, with the bucket name injected
as the `TF_STATE_BUCKET` repository variable. Without that variable the state would be local
to the runner and lost after the run.

**One NAT Gateway per VPC** keeps cost down but makes a single AZ a point of failure for
outbound traffic. Production would use one per AZ.

**The EKS API endpoint is public** so GitHub-hosted runners can run `kubectl`. Nodes remain
private. Hardening would mean a private endpoint with self-hosted runners inside the VPC, or
at minimum restricting `public_access_cidrs`.

**Load balancers use the in-tree Kubernetes integration.** I used the built-in
`type: LoadBalancer` NLB support rather than installing the AWS Load Balancer Controller,
which would need an IRSA provider and additional IAM roles under the account's allowed
prefixes.

**The backend hostname is resolved when NGINX starts.** The pipeline restarts the proxy on
every deploy so a new NLB hostname is picked up. A runtime `resolver` directive would be more
robust.

**IAM surface is minimal:** only the `eks-*` cluster and node roles are created by Terraform.
No `sentinel-*` role is needed because there is no IRSA in this PoC; the `sentinel-chacon-gha-v2`
role exists outside Terraform as the pipeline's own identity, which is the correct place for
it — a deployer role should not be managed by the deployment it authorizes.

**Nodes are `t3.medium`, two per cluster**, to keep cost low. The Kubernetes version is a
variable (`kubernetes_version`) in case the default is not offered in a given account.

**There is no TLS**; the public endpoint is plain HTTP.

## What I would add next

TLS at the edge with an ACM certificate and an HTTPS listener, and mTLS between proxy and
backend through a service mesh. A default-deny `NetworkPolicy` in both clusters. The AWS Load
Balancer Controller with IRSA, plus WAF in front of the public NLB.

On the operational side: CloudWatch Container Insights or Prometheus/Grafana, VPC Flow Logs
along the peering path, one NAT Gateway per AZ, private API endpoints with self-hosted
runners, `terraform plan` output posted to pull requests, and separate environments with
their own state.

Longer term, the peering would give way to Transit Gateway or PrivateLink once more VPCs or
stricter isolation are involved. PrivateLink in particular would expose only the backend
service rather than a whole network path, which is a better fit for the isolation this
architecture is trying to express.