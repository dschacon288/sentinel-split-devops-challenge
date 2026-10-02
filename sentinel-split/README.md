# Rapyd Sentinel – Split Architecture PoC

Two isolated VPCs, one EKS cluster in each, private connectivity through VPC peering, and a
GitHub Actions pipeline that builds everything and proves it works end to end.

```
                     Internet
                        │
                ┌───────▼────────┐
                │ Public NLB     │   (internet-facing, public subnets of vpc-gateway)
                └───────┬────────┘
   ┌────────────────────▼─────────────────────┐        ┌───────────────────────────────────────┐
   │ vpc-gateway 10.0.0.0/16                  │        │ vpc-backend 10.1.0.0/16               │
   │  eks-gateway (nodes: private subnets)    │        │  eks-backend (nodes: private subnets) │
   │  nginx reverse proxy  ───────────────────┼─ VPC ──┼──► Internal NLB ──► backend pods      │
   │  NAT GW (public subnet)                  │ peering│     "Hello from backend"              │
   └──────────────────────────────────────────┘        │  NAT GW (public subnet)               │
                                                       └───────────────────────────────────────┘
```

## Repository layout

```
terraform/
  main.tf, variables.tf, outputs.tf, versions.tf   # root module: wires the modules together
  modules/
    networking/   # VPC, 2 private + 2 public subnets (2 AZs), IGW, NAT GW, route tables
    eks/          # IAM roles (eks- prefix), EKS cluster, managed node group
    peering/      # VPC peering, routes in both directions, backend security group rule
k8s/
  backend/        # namespace, nginx "Hello from backend", internal NLB Service
  gateway/        # namespace, nginx reverse proxy, public NLB Service
.github/workflows/
  deploy.yml      # validate -> lint -> plan -> apply -> deploy -> end-to-end test
  destroy.yml     # manual teardown
```

## How to clone and run

Terraform is **never** applied from a laptop; the pipeline does it.

1. Create a GitHub repository and push this project to `main`.
2. Add credentials as repository **secrets** (pick one):
   - Static keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (and `AWS_SESSION_TOKEN` if the credentials are temporary).
   - OIDC (bonus, no long-lived keys): `AWS_ROLE_ARN`, pointing to a role that trusts GitHub's OIDC provider for this repo.
3. *(Recommended)* Create an S3 bucket for Terraform state and add its name as the repository **variable** `TF_STATE_BUCKET`. Without it the state is local to the runner (see limitations).
4. Push to `main`. The `deploy` workflow runs automatically. Pushes to other branches run validation, lint and `terraform plan` only.
5. Open the run summary: the last step prints the public URL and the response, which should be `Hello from backend`.

To tear everything down: run the `destroy` workflow manually (requires `TF_STATE_BUCKET`).

## Networking

| | vpc-gateway | vpc-backend |
|---|---|---|
| CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| Private subnets (nodes, pods) | 2 × /20 in 2 AZs | 2 × /20 in 2 AZs |
| Public subnets | 2 × /24, used only by the NAT Gateway and the public NLB | 2 × /24, used only by the NAT Gateway |
| Outbound | NAT Gateway | NAT Gateway |
| EC2 instances with public IPs | none | none |

- **Peering:** `vpc-gateway` requests and `vpc-backend` accepts (same account and region, auto-accepted).
- **Routes:** each VPC has a route to the other VPC's CIDR through the peering connection, in both the private and public route tables, so return traffic always works.
- **Security groups:** the EKS-managed cluster security group of the backend nodes gets one extra ingress rule: TCP 30000-32767 (the NodePort range used by the NLB) **only from the gateway VPC CIDR**. Nothing else from outside the backend VPC is allowed. The Kubernetes Service also sets `loadBalancerSourceRanges` to the gateway CIDR, so the restriction exists at two layers.
- The CIDRs are non-overlapping, which peering requires.

## How the proxy reaches the backend

1. The pipeline creates the backend Service of type `LoadBalancer` with the annotation for an **internal** NLB. AWS places it in the private subnets of `vpc-backend`.
2. The pipeline reads the NLB's DNS name and renders it into the gateway NGINX config (`proxy_pass http://<internal-nlb-dns>`).
3. That DNS name resolves to private `10.1.x.x` addresses. From a gateway pod the traffic goes: node → route `10.1.0.0/16` via the peering connection → internal NLB → backend node NodePort (allowed by the security group rule) → backend pod.
4. Clients on the internet hit the public NLB of the gateway, which forwards to the NGINX pods.

## CI/CD pipeline overview

`deploy.yml` runs on every push (and manually):

1. **validate** – `terraform fmt -check`, `terraform validate`, `tflint` (bonus), and offline schema validation of the manifests with `kubeconform`.
2. **deploy** (plan on every branch, apply and deploy on `main` only):
   - AWS login via OIDC if `AWS_ROLE_ARN` exists, static keys otherwise.
   - `terraform init / plan / apply`.
   - Kubeconfig for both clusters, wait for nodes.
   - Backend: `kubectl apply --dry-run=server` (bonus), apply, wait for the internal NLB.
   - Gateway: render the backend hostname, dry-run, apply, wait for the public NLB.
   - **End-to-end test:** `curl` the public URL until it returns `Hello from backend`.
   - **Negative test:** the backend's internal NLB must not be reachable from the runner (the internet).

## Trade-offs and limitations

- **Terraform state:** if `TF_STATE_BUCKET` is not set, state is local to the runner and lost after the run, so a second run would try to recreate resources. The S3 backend fixes this; I could not verify in advance whether the challenge account permits creating/using a bucket.
- **Single NAT Gateway per VPC:** cheaper, but a single AZ is a point of failure for outbound traffic. Production would use one per AZ.
- **Public EKS API endpoint:** kept so GitHub-hosted runners can run `kubectl`. Nodes are private. In production: private endpoint plus self-hosted runners inside the VPC, or restrict `public_access_cidrs`.
- **In-tree Service load balancers:** I used the Kubernetes built-in `type: LoadBalancer` support (NLB) to avoid installing the AWS Load Balancer Controller, which needs an OIDC provider and extra IAM roles (`sentinel-*` or `eks-*` prefix only).
- **Backend hostname resolved at NGINX start:** the pipeline restarts the proxy on every deploy so a new NLB hostname is picked up. A runtime `resolver` would be more robust.
- **IAM:** only `eks-*` roles are created (cluster and node roles). I did not need any `sentinel-*` role because there is no IRSA in this PoC. If an IAM, S3 or EKS action had been denied by the scoped account, the intended fix in a real environment is a dedicated deployer role with the minimum required actions, rather than working around the limit.
- **Node type and count:** `t3.medium`, 2 nodes per cluster, to keep cost low.
- **Kubernetes version** is a variable (`kubernetes_version`); set it to a version available in the account if the default is not offered.
- No TLS: the public endpoint is plain HTTP.

## What I would add next

- TLS at the edge (ACM certificate, HTTPS listener) and mTLS between proxy and backend (service mesh).
- `NetworkPolicy` for default-deny in both clusters.
- AWS Load Balancer Controller with IRSA, plus WAF in front of the public NLB.
- Observability: CloudWatch Container Insights or Prometheus/Grafana, VPC Flow Logs on the peering path.
- One NAT Gateway per AZ, private API endpoints with self-hosted runners, Terraform plan posted to pull requests, and separate environments (dev/stage/prod) with their own state.
- Replace the peering with Transit Gateway or PrivateLink when more VPCs or stricter isolation are needed. PrivateLink would expose only the backend service instead of a whole network path.
