# EnterpriseBot-task
This repo hold Assignment for enterpriseBot 
## Repository Layout

```
.
├── setup.sh                     # Part 3 — One-command idempotent cluster & app bootstrap
├── README.md                    # Part 6 — Architecture, trade-offs, and verification
├── ANSWERS.md                   # Part 5 — Gateway API zero-downtime migration strategy
├── service/                     # Part 1 — Microservice source, multi-stage Dockerfile, .dockerignore
│   ├── main.py
│   ├── Dockerfile
│   └── .dockerignore
├── chart/                       # Part 2 — Parametrized Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── configmap.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
├── lab/                         # Part 4 — Debugging lab fixes & documentation
│   ├── scenario.sh              # Driver script (unmodified)
│   ├── cluster-state/           # Pristine cluster guardrails & namespace (unmodified)
│   ├── broken-chart/            # Fixed chart templates & values
│   ├── FINDINGS.md              # Detailed RCA, symptoms, and fixes for 6 defects
│   └── part4-session.log        # Recorded terminal debugging session
└── .github/
    └── workflows/
        └── ci.yml               # Bonus — GitHub Actions CI with Helm lint, Docker build & Trivy scan
```

---

## Part 1 — Microservice Design

The microservice is implemented in Python 3 utilizing standard library modules (`http.server`, `json`, `os`, `socket`) to maintain a clean, zero-dependency footprint.

* **Endpoints:**
  * `GET /`: Returns JSON `{"app": "<APP_NAME>", "version": "<VERSION>", "pod": "<hostname>"}`. `APP_NAME` and `VERSION` are dynamically retrieved from environment variables at runtime.
  * `GET /healthz`: Returns HTTP `200 OK` with payload `ok`.
* **Dockerfile Hardening:**
  * **Multi-stage build:** Uses `python:3.12.7-alpine` as builder to compile Python bytecode, and an independent clean `python:3.12.7-alpine` runtime image.
  * **Non-root execution:** Runs as dedicated system user `appuser` (UID 10001, GID 10001).
  * **Pinned base image:** Strictly pinned to patch tag `3.12.7-alpine` (not `latest`).
  * **Zero third-party CVE surface:** Zero pip dependencies ensures clean Trivy vulnerability scans with 0 HIGH/CRITICAL findings.

---

## Part 2 — Helm Chart Design

The Helm chart in `chart/` is fully decoupled and parameterizable without hardcoded values:
* **ConfigMap Integration:** `APP_NAME` and `VERSION` are supplied via a ConfigMap template (`templates/configmap.yaml`) rendered from `.Values.config`. The deployment mounts these via `envFrom: [configMapRef]`.
* **ConfigMap Change Detection:** The deployment template contains an annotation checksum `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}` to trigger automatic rolling updates when configuration changes.
* **Probes:** Configured with `readinessProbe` and `livenessProbe` checking `httpGet: /healthz` on the named HTTP port.
* **Security Context:** `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, and drops all capabilities (`capabilities.drop: ["ALL"]`).

---

## Part 3 — How to Run and Verify

### Prerequisites
* Docker
* `kind`
* `kubectl`
* `helm`

### 1. One-Command Setup
Execute the bootstrap script from the repository root:
```bash
./setup.sh
```

The script is completely **idempotent**; executing it multiple times safely reuses the cluster, ensures ingress-nginx is ready, updates the image, and upgrades the Helm release without error.

### 2. Verification Commands

Test the service through the Ingress controller:
```bash
# Verify GET / returns dynamic JSON metadata
curl -s -H "Host: demo.local" http://localhost/

# Expected Output:
# {
#   "app": "demo-app",
#   "version": "1.0.0",
#   "pod": "demo-demo-service-xxxxxxxxxx-xxxxx"
# }

# Verify healthz probe endpoint
curl -s -I -H "Host: demo.local" http://localhost/healthz
# Expected HTTP/1.1 200 OK
```

Test chart value override compatibility:
```bash
helm upgrade demo ./chart --namespace demo \
  --set replicaCount=3 \
  --set config.appName="enterprise-bot-rocks" \
  --set config.version="2.5.0"

# Verify updated runtime output
curl -s -H "Host: demo.local" http://localhost/
```

### 3. Running the Part 4 Debug Lab
```bash
cd lab
./scenario.sh up
./scenario.sh verify
```
Expected output: **ALL GREEN — 11/11 checks passed.**

---

## Resource Requests and Limits Rationale

In `chart/values.yaml`, resources are set to:
```yaml
resources:
  requests:
    cpu: "50m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "128Mi"
```

* **Requests (`50m` CPU / `64Mi` RAM):**
  * The Python microservice has an idle memory footprint of ~18-24MB under Alpine Linux. Allocating `64Mi` gives a comfortable 2.5x buffer over baseline memory without over-allocating cluster node capacity.
  * A `50m` (0.05 core) request ensures high packing density on Kubernetes worker nodes while guaranteeing the Linux CFS scheduler allocates sufficient CPU slices during concurrent request handling.
* **Limits (`200m` CPU / `128Mi` RAM):**
  * `200m` CPU limit allows 4x burst capability during JSON parsing, high request concurrency, or rolling restarts without starving adjacent workloads.
  * `128Mi` memory limit caps potential memory leaks while providing ample headroom for memory spikes, preventing node OOM thrashing.

---

## What Was Deliberately Skipped and the Associated Risks

1. **PodDisruptionBudget (PDB):**
   * *Skipped:* A `PodDisruptionBudget` resource ensuring `minAvailable: 1`.
   * *Risk:* During voluntary cluster operations (e.g., node upgrades, drainage), both replicas could theoretically be evicted simultaneously, causing temporary service unavailability.
2. **HorizontalPodAutoscaler (HPA):**
   * *Skipped:* Dynamic horizontal autoscaling based on CPU/Memory or RPS metrics.
   * *Risk:* Static replica count (2) cannot scale up to meet unexpected traffic spikes, leading to increased latency or request queuing.
3. **Automated Secret Management / External Secrets:**
   * *Skipped:* HashiCorp Vault / AWS Secrets Manager integration.
   * *Risk:* Not critical for this stateless demo, but in production, secrets stored in plain ConfigMaps or unencrypted Kubernetes Secrets create credential exposure risks.
4. **TLS Termination / Cert-Manager:**
   * *Skipped:* Ingress TLS block with automated Let's Encrypt certificates.
   * *Risk:* Ingress operates on plaintext HTTP (`port 80`), unsuitable for sensitive production traffic without an upstream SSL termination proxy or Cloudflare tunnel.

---

## Production-Ready Recommendations

If transitioning this deployment to an enterprise production environment:
1. **NetworkPolicies:** Enforce default-deny ingress/egress policies, permitting traffic only from the `ingress-nginx` controller namespace and blocking unwanted cross-namespace lateral movement.
2. **Observability & Metrics:** Export Prometheus metrics (e.g. `/metrics` endpoint measuring request duration, latency histograms, error counters) and configure OpenTelemetry distributed tracing.
3. **Graceful Shutdown & Connection Draining:** Implement `SIGTERM` signal handling in `main.py` with `httpd.shutdown()` and a `preStop` hook sleep (`sleep 5`) to allow iptables/kube-proxy connection draining before pod termination.
4. **Multi-Arch OCI Images:** Build multi-architecture container images (`linux/amd64`, `linux/arm64`) with GitHub Actions `docker/buildx` to support both AWS Graviton and x86 nodes.

---

## How I Used AI

In accordance with Enterprise Bot's AI policy:
* **Tools Used:** Gemini assistant / code generation agents.
* **Use Cases:**
  * Rapidly generating boilerplate scaffolding for `chart/templates/_helpers.tpl` and initial `FINDINGS.md` markdown structuring.
  * Brainstorming edge cases for the Gateway API zero-downtime migration strategy in `ANSWERS.md`.
* **What I Had to Correct / Refine:**
  * AI-generated Helm templates initially lacked the `checksum/config` annotation required to trigger pod rollouts upon ConfigMap modification; added explicit SHA256 checksum hashing.
  * Carefully reviewed and cross-referenced Kubernetes Job specifications (`restartPolicy` constraints) and LimitRange admission controller error behaviors against real Kubernetes API standards.
  * Refined `setup.sh` cluster creation config to properly register Kind `extraPortMappings` for host ports 80/443, ensuring seamless native port routing.

