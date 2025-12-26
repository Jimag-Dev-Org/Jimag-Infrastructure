# Jimag Autos – AWS / EKS Infrastructure Architecture

## 1. Goals

This document describes how we deploy Jimag Autos on AWS using:

- A **single cost-optimized EKS cluster** (for now),
- Namespaces for **dev**, **preprod**, and **prod**,
- AWS managed services for database, storage, and auth,
- A layout that can evolve into **multi-region** and **multi-account** like a real-world setup.

This is both a **practical implementation plan** for this project and a **learning template** for production-grade designs.

---

## 2. High-level design

### 2.1 AWS Account & Region

- **Account (lab):** 1 AWS account (e.g. `jimag-sandbox`)
  - All environments (dev, preprod, prod) live here for cost reasons.
- **Primary region:** `us-east-1`
  - All core resources (EKS, RDS, S3, etc.) are initially in this region.

> **Real-world note:**  
> In production, we’d typically use **multiple AWS accounts**:
> - `shared-services` (central tools, maybe CI/CD, shared VPCs),
> - `dev`, `staging/preprod`, `prod`.  
> Each account might host its own EKS cluster(s). Our Terraform layout will be designed so we *could* split to multiple accounts later by changing providers and remote state configuration.

---

## 3. Kubernetes Cluster (EKS)

### 3.1 Cluster

- **Cluster name:** `jimag-eks-us-east-1`
- **Region:** `us-east-1`
- **Version:** Recent EKS Kubernetes version (e.g. 1.30, configured via Terraform).

### 3.2 Node groups

- **Single managed node group** initially:
  - Instance type: small general purpose (e.g. `t3.small` or similar),
  - Min size: `2` nodes,
  - Max size: maybe `4–5` nodes (for autoscaling headroom),
  - Nodes spread across **at least 2 AZs** (e.g. `us-east-1a`, `us-east-1b`).

> This gives us basic HA: if one node or AZ fails, workloads can still run on the other.

### 3.3 Namespaces by environment

We use **namespaces** to separate environments inside the single cluster:

- `dev`      – development workloads
- `preprod`  – staging/preprod workloads
- `prod`     – production workloads
- `argocd`   – GitOps controller (Argo CD)
- `monitoring` – Prometheus, Grafana, Alertmanager, etc.

Guardrails to simulate real-world isolation:

- **ResourceQuota & LimitRange** per env:
  - Prevent dev from consuming all CPU/memory and starving prod.
- **NetworkPolicy** (later):
  - Restrict cross-namespace communication where appropriate.
- **Ingress separation:**
  - Different hostnames per env, e.g.:
    - `dev.jimagautos.example.com` → namespace `dev`
    - `preprod.jimagautos.example.com` → namespace `preprod`
    - `www.jimagautos.example.com` (or `app.jimagautos.com`) → namespace `prod`

> **Real-world note:**  
> Most production setups keep **prod in its own cluster** to avoid blast radius. Here, we trade strict isolation for cost, but we’ll design the manifests and Terraform so that splitting into `eks-dev`, `eks-preprod`, and `eks-prod` clusters later would mainly be a matter of:
> - Deploying the same modules in different clusters/accounts,
> - Repointing ArgoCD apps to each cluster.

---

## 4. Supporting AWS Services

### 4.1 Container registry – ECR

- **ECR repos:**
  - `jimag-inventory-svc`
  - `jimag-car-website-frontend`

CI pipelines will:

- Build Docker images,
- Tag them with `<app>:<git-sha>` (and maybe `<app>:<env>-<version>`),
- Push to ECR,
- GitOps (ArgoCD) will deploy images by tag from Kubernetes manifests/Helm charts.

### 4.2 Database – RDS Postgres

For cost, we’ll start with **one RDS instance** and separate logical databases per env:

- RDS instance: `jimag-rds-postgres`
- Databases:
  - `jimag_inventory_dev`
  - `jimag_inventory_preprod`
  - `jimag_inventory_prod`

Application configuration uses different `DATABASE_URL` per namespace.

> **Real-world note:**  
> A stricter setup would use:
> - Separate RDS instances per environment, or
> - Separate AWS accounts entirely.  
> For this lab project, multiple databases on one instance balance cost with realism.

### 4.3 Object storage – S3 (car images)

- **Bucket:** `jimag-autos-images`
- Folder/key prefixes per env:
  - `dev/…`
  - `preprod/…`
  - `prod/…`

Application env vars:

- `S3_BUCKET=jimag-autos-images`
- `S3_PREFIX=dev/` | `preprod/` | `prod/` depending on namespace.

Later we can front this with **CloudFront** as a CDN for faster image delivery.

### 4.4 Email – SES (later)

Used for:

- Welcome emails on signup,
- Possibly lead notifications.

We’ll integrate SES once auth/sign-up flows are in place.

### 4.5 Auth – Cognito (later)

Cognito User Pool for:

- User signup/login flows on the frontend,
- JWT verification in the backend (`inventory-svc`),
- Role-based or claims-based access control.

Each namespace (dev/preprod/prod) may point to a different user pool or app client configuration.

---

## 5. Ingress, Networking & Security

### 5.1 Ingress

- **AWS Load Balancer Controller** installed in the cluster:
  - Uses Kubernetes `Ingress` resources to create an ALB.
- Each environment has its own **Ingress** in its namespace, matching different hostnames.

Example:

- `dev.jimagautos.example.com` → Ingress in `dev` namespace → services in `dev`
- `preprod.jimagautos.example.com` → Ingress in `preprod`
- `jimagautos.example.com` or `www.jimagautos.com` → Ingress in `prod`

TLS certificates via:

- **ACM** (AWS Certificate Manager), with:
  - One or multiple certs for the domains,
  - ALB configured to use these certs.

### 5.2 Networking

- VPC with public/private subnets across at least **2 AZs**.
- EKS node groups in **private subnets**.
- ALB in **public subnets**, forwarding to nodes via node ports/target groups.
- RDS and any internal services in **private subnets** only.

> **Real-world multi-account note:**  
> In a multi-account world, VPCs might live in each account and be connected via VPC peering or Transit Gateway. Our Terraform layout will keep VPC and EKS config modular so it could be reused in such a setup.

---

## 6. Observability

### 6.1 Metrics

- **Prometheus** (likely via `kube-prometheus-stack` Helm chart) deployed to `monitoring` namespace.
- Scrapes:
  - `inventory-svc` `/metrics` endpoint in each env (dev/preprod/prod namespaces),
  - Kubernetes components (apiserver, kubelet, etc.),
  - Node exporter (for CPU, memory, network),
  - cAdvisor (container-level metrics).

- **Grafana**:
  - Dashboards for:
    - Inventory service HTTP metrics,
    - Process metrics (Node.js CPU, heap, event loop),
    - Cluster/node health,
    - SLO views for `/api/cars` and `/api/cars/:id`.

### 6.2 Logging

- Application logs:
  - `inventory-svc` logs structured JSON to stdout/stderr via `HttpLoggingInterceptor`.
- Cluster logging:
  - Fluent Bit/Fluentd (or similar) to ship pod logs to:
    - CloudWatch Logs (most likely for this project).

Searchable fields:

- `service`, `env` (`dev`/`preprod`/`prod`),
- `method`, `route`, `statusCode`,
- `level` (`info`, `error`).

### 6.3 Alerting

- Alertmanager hooked to Prometheus:
  - Alerts on:
    - High 5xx for `inventory-svc`,
    - Latency SLO violation,
    - Pod CrashLoopBackOff / OOMKilled,
    - Node resource exhaustion.
- Each alert includes a `runbook_url` annotation pointing to the appropriate section in:
  - `docs/runbook-inventory-svc.md`

---

## 7. GitOps & Deployments

### 7.1 Repositories

- **App repos:**
  - `inventory-svc`
  - `car-website-frontend`
- **(Planned) Infra/config repo:**
  - e.g. `jimag-infra-live` (could be a folder in this repo initially)
  - Holds:
    - Kubernetes manifests / Helm values,
    - Argo CD `Application` and `AppProject` definitions.

### 7.2 Argo CD (App of Apps)

- Argo CD installed in `argocd` namespace of the single EKS cluster.
- Uses an “app of apps” pattern:
  - One root `Application` defines:
    - dev apps (in `dev` ns),
    - preprod apps (in `preprod` ns),
    - prod apps (in `prod` ns).

Promotion flow (simplified):

1. CI builds image and updates manifests (or Helm values) in Git.
2. `dev` path is updated first → ArgoCD syncs to `dev` namespace.
3. Once validated, changes are promoted to `preprod` path.
4. Finally, changes promoted to `prod` path.

> **Real-world note:**  
> With multiple clusters (e.g. `eks-dev`, `eks-preprod`, `eks-prod` in different accounts/regions), you’d have:
> - One ArgoCD instance per cluster **or**
> - One central ArgoCD with multiple clusters registered as targets.  
> Each `Application` would point to the appropriate cluster + namespace.

---

## 8. Future: Multi-region & Multi-cluster

Even though we start with a **single cluster in one region**, the architecture is designed to extend to:

- Another region (e.g. `us-west-2`) with:
  - A second EKS cluster (`jimag-eks-us-west-2`),
  - Possibly a read replica or DR strategy for Postgres,
  - S3 replication for images (cross-region replication).
- Separate prod cluster per region with traffic managed by:
  - Route 53 (latency-based routing or failover),
  - Or CloudFront with origin groups.

Terraform-wise:

- EKS, VPC, RDS, and S3 are implemented as **modules**.
- Each env/region combination is a small root Terraform config that:
  - Imports the modules,
  - Passes `env`, `region`, and sizing parameters.

This allows us to move from:

- “1 account, 1 cluster, multi-namespace” → **now**
- to “multi-account, multi-cluster, multi-region” → **future**  
  without rewriting everything from scratch.

