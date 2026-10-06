# shortlink-k8s-terraform

[![ci](https://github.com/Anubhavjain786/shortlink-k8s-terraform/actions/workflows/ci.yml/badge.svg)](https://github.com/Anubhavjain786/shortlink-k8s-terraform/actions/workflows/ci.yml)

A small URL shortener (FastAPI + Redis) used as a vehicle for the interesting part: running it on Kubernetes the way a production service should run, with every piece of infrastructure managed by Terraform.

The same Terraform modules deploy to two targets:

| Environment | Cluster | Status |
|---|---|---|
| `infra/local` | [kind](https://kind.sigs.k8s.io/) on your laptop, 3 nodes | Applied and tested end to end. Costs nothing. |
| `infra/aws` | Amazon EKS in a new VPC, image in ECR | Passes `terraform validate`. **Never applied**, because it costs money. |

## What is in here

```
app/                     FastAPI service: create links, redirect, stats, health, Prometheus metrics
tests/                   pytest suite (runs against an in-memory fake Redis)
Dockerfile               multi-stage build, non-root user
deploy/helm/shortlink/   Helm chart: Deployment, Service, HPA, PodDisruptionBudget, Ingress, ServiceAccount
infra/modules/redis/     Terraform module: Redis StatefulSet + headless Service + persistent volume
infra/modules/shortlink/ Terraform module: the Helm release for the app
infra/local/             Terraform root for kind (namespace, metrics-server, Redis, app)
infra/aws/               Terraform root for AWS (VPC, EKS, ECR, then the same two modules)
kind/cluster.yaml        local cluster definition
.github/workflows/ci.yml tests, Terraform + Helm validation, and a full deploy to kind on every push
```

## Architecture

```
            localhost:8080                      (AWS: a LoadBalancer Service instead)
                  |
        kind port mapping -> NodePort 30080
                  |
          Service "shortlink"
           /        |        \
       pod         pod        pod        Deployment, 2 to 5 replicas
        \           |          /         scaled by a HorizontalPodAutoscaler on CPU
         \          |         /          spread across nodes, non-root, read-only filesystem
          Service "redis" (headless)
                    |
                 redis-0                 StatefulSet with a PersistentVolumeClaim (append-only file)
```

Terraform owns all of it: the namespace, the metrics-server release, the Redis StatefulSet (Kubernetes provider) and the app release (Helm provider).

## Run it locally

You need Docker, [kind](https://kind.sigs.k8s.io/), `kubectl` and Terraform 1.6 or newer.

```bash
brew install kind kubectl terraform
```

```bash
make up
```

`make up` creates the cluster, builds the image, loads it into the nodes, runs `terraform apply` and finishes with a smoke test. Then:

```bash
curl -s -X POST localhost:8080/links -H 'content-type: application/json' -d '{"url":"https://example.com"}'
```

```bash
make status
```

```bash
make load-test
```

Tear down with `make destroy` (removes what Terraform created) and `make down` (deletes the cluster). Run `make help` for every target.

## What was verified, and how

Everything in this table was run against the kind cluster (Kubernetes 1.36, three nodes), not assumed.

| Behaviour | How it was tested | Result |
|---|---|---|
| Deploy from nothing | `terraform apply` on an empty cluster | 5 resources created, app answering in under a minute |
| End to end | `scripts/smoke.sh`: health, create link, follow it, read hit count | Pass |
| Redis outage | Deleted `redis-0` while polling | `/readyz` returned 503, `/healthz` stayed 200, app containers restarted 0 times |
| Data survives a Redis restart | Created a link, deleted the Redis pod, followed the link after it came back | Still redirects (volume re-attached) |
| Self-healing | Deleted an app pod while sending requests | 40 of 40 requests succeeded |
| Zero-downtime rollout | Changed the image tag through Terraform under constant traffic | See "Lessons" below: 4 of 242 failed before the fix, 0 of 623 after |
| Autoscaling | 12 parallel request loops from inside the cluster | CPU hit 166% of request, replicas went 3 to 5 within 60 seconds |
| Unit tests | `make test` | 6 passed |
| CI | GitHub Actions: tests, Terraform and Helm validation, deploy to kind, smoke test | Green on every push |

## Lessons from building it

These are the things that did not work the first time. They are the most useful part of the project.

**1. Terraform did not notice chart changes.** After editing a template in the local chart, `terraform plan` said "No changes". With a local chart path the Helm provider only compares the chart version and the values, not the files. Fix: `infra/modules/shortlink` hashes every chart file and passes the hash in as a value, so any chart edit shows up in the plan.

**2. Rolling updates dropped requests.** The first rollout under load failed 4 of 242 requests with connection errors. When a pod is deleted, Kubernetes sends it SIGTERM and removes it from the Service endpoints at the same time, and for a moment kube-proxy still routes to a server that has stopped listening. Fix: a 5 second `preStop` sleep in the Deployment, so the pod keeps serving while it is being removed from rotation. Three further rollouts: 0 of 623 failed.

**3. The autoscaler scaled up on startup.** With a CPU request of 50m, the HPA went from 2 to 3 replicas right after deploy with no traffic at all. Utilisation is measured as a percentage of the *request*, so Python's startup CPU burst looked like 94% load. Fix: a more honest request of 100m.

**4. Liveness and readiness must check different things.** Liveness (`/healthz`) only says the process is up. Readiness (`/readyz`) pings Redis. If liveness also checked Redis, a Redis outage would make Kubernetes restart every app pod, which helps nobody. With the split, the pods just drop out of the Service until Redis returns.

## Design choices

- **One chart, two Terraform roots, shared modules.** Local and AWS differ only in the cluster underneath and in how the Service is exposed. The app and Redis definitions are not duplicated.
- **Helm for the app, plain Kubernetes resources for Redis.** This shows both providers. In production I would use a managed Redis (ElastiCache) and delete the Redis module.
- **`atomic = true` on the Helm release.** A failed rollout rolls back by itself instead of leaving a half-deployed release.
- **Security defaults.** Non-root user, read-only root filesystem, all Linux capabilities dropped, default seccomp profile, service account token not mounted.
- **Availability defaults.** `maxUnavailable: 0` rollouts, a PodDisruptionBudget, and topology spread across nodes.

## The AWS environment

`infra/aws` creates a VPC with private and public subnets across three zones, an EKS cluster with a managed node group, the EBS CSI driver and metrics-server add-ons, and an ECR repository with scan-on-push and a lifecycle policy. It then deploys Redis and the app with the same modules, exposed through a LoadBalancer Service.

It has been validated but not applied. Before a first real run you would:

1. Uncomment the S3 backend in `infra/aws/versions.tf` so state is remote and locked.
2. `terraform apply -target=module.vpc -target=module.eks -target=aws_ecr_repository.shortlink` to create the cluster first, because the Kubernetes and Helm providers need it to exist.
3. Build and push the image to the ECR URL from the outputs.
4. `terraform apply -var image_tag=<tag>` for the workloads.

Expect roughly the cost of one EKS control plane, two `t3.medium` nodes and one NAT gateway while it is up. Run `terraform destroy` when done.

## What I would add next

- Managed Redis and a NetworkPolicy that only lets the app reach it.
- Gateway API routes with TLS instead of a bare LoadBalancer.
- Image build and push from CI with the Git SHA as the tag, and a deploy job per environment.
- Alerts on the Prometheus metrics the app already exposes at `/metrics`.
