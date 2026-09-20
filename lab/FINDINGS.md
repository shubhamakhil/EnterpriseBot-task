# Part 4 — Findings

## Defect 1 — Incorrect Container Port

**Symptom**

The readiness probe was failing with a connection refused error:

```text
Readiness probe failed: Get "http://10.244.0.126:8080/healthz":
dial tcp 10.244.0.126:8080: connect: connection refused
```

The application logs showed that the container was actually listening on port `8081`:

```text
listening on :8081 (image default is 8081; set PORT to override)
```

**Cause**

The Helm chart configured the application to use port `8080`, while the application image listens on port `8081` by default.

**Fix**

Changed the application/service port configuration from `8080` to `8081`.

**How I found it**

```bash
kubectl get pods -n debug-lab
kubectl describe pod <pod-name> -n debug-lab
kubectl describe deployment <deployment-name> -n debug-lab
```

The readiness probe was targeting port `8080`, while the application logs confirmed that it was listening on `8081`.

**Verification**

After applying the fix:

```bash
kubectl get pods -n debug-lab
```

Confirmed the affected Pod became `Ready`.

I also verified the application endpoint:

```bash
kubectl exec -n debug-lab <pod-name> -- wget -qO- http://127.0.0.1:8081/healthz
```

Expected result:

```text
{"status":"ok"}
```

---

## Defect 2 — Non-Root User Could Not Be Verified

**Symptom**

The container failed to start with:

```text
Error: container has runAsNonRoot and image has non-numeric user (nonroot),
cannot verify user is non-root
```

**Cause**

The workload used:

```yaml
runAsNonRoot: true
```

but did not specify a numeric `runAsUser`. The image defines its user by name, so Kubernetes could not verify that the configured user was non-root.

**Fix**

Added:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
```

This explicitly runs the container process as UID `65532`.

**How I found it**

```bash
kubectl describe pod <pod-name> -n debug-lab
kubectl describe deployment <deployment-name> -n debug-lab
```

The Pod events contained the `runAsNonRoot` error.

**Verification**

Verified the Pod became healthy:

```bash
kubectl get pods -n debug-lab
```

Then verified the effective user inside the container:

```bash
kubectl exec -n debug-lab <pod-name> -- id
```

Expected result should show UID `65532` and not UID `0`.

---

## Defect 3 — Invalid Migration Job Restart Policy

**Symptom**

The migration Job was not created successfully.

**Cause**

The Job template used an invalid restart policy:

```text
Job.batch "migrate" is invalid:
spec.template.spec.restartPolicy: Required value:
valid values: "OnFailure", "Never"
```

**Fix**

Changed the Job to:

```yaml
restartPolicy: OnFailure
```

**How I found it**

The Kubernetes error identified the invalid `restartPolicy` directly. I inspected the workload and related events:

```bash
kubectl describe pod <pod-name> -n debug-lab
kubectl describe job migrate -n debug-lab
```

**Verification**

Verified that the migration Job completed successfully:

```bash
kubectl get job migrate -n debug-lab
```

Expected:

```text
COMPLETIONS   1/1
```

I also verified the Job condition:

```bash
kubectl get job migrate -n debug-lab \
  -o jsonpath='{.status.succeeded}{"\n"}'
```

Expected:

```text
1
```

---

## Defect 4 — Incorrect Gateway Backend URL

**Symptom**

The Gateway was not able to communicate with the backend Service.

**Cause**

The Gateway was configured with the wrong namespace:

```yaml
BACKEND_URL: "http://backend.default.svc:8080"
```

The backend Service exists in the `debug-lab` namespace.

**Fix**

Changed the configuration to:

```yaml
BACKEND_URL: "http://backend.debug-lab.svc:8080"
```

**How I found it**

Inspected the Gateway Pod and Deployment:

```bash
kubectl describe pod <pod-name> -n debug-lab
kubectl describe deployment <deployment-name> -n debug-lab
```

The configured `BACKEND_URL` showed that the Gateway was attempting to reach the backend in the `default` namespace.

**Verification**

Verified the Gateway's status endpoint:

```bash
kubectl exec -n debug-lab <gateway-pod> -- \
  wget -qO- http://127.0.0.1:8080/status
```

I also verified the complete path from inside the cluster:

```bash
wget -qO- http://gateway.debug-lab.svc/status
```

Expected response included:

```json
"backend":"ok"
```

This confirmed that the Gateway could resolve and communicate with the backend Service.

---

## Defect 5 — Worker Missing Writable Cache Directory

**Symptom**

The Worker failed to initialize its cache:

```text
FATAL: worker could not initialise its cache:
mkdir /var/cache/app: read-only file system
```

**Cause**

The application requires a writable directory at:

```text
/var/cache/app
```

but the container filesystem did not provide a writable location there.

**Fix**

Added an `emptyDir` volume and mounted it at:

```yaml
volumeMounts:
  - name: worker-volume
    mountPath: /var/cache/app
```

**How I found it**

Inspected the Worker Pod and Deployment:

```bash
kubectl describe pod <pod-name> -n debug-lab
kubectl describe deployment <deployment-name> -n debug-lab
```

The application error identified `/var/cache/app` as the location where the write operation was failing.

**Verification**

Verified that the Worker became Ready:

```bash
kubectl get pods -n debug-lab -l app=worker
```

Then verified the mounted directory from inside the container:

```bash
kubectl exec -n debug-lab <worker-pod> -- \
  sh -c 'touch /var/cache/app/verify && ls -l /var/cache/app/verify'
```

Successful file creation confirmed that the application has a writable cache directory.

---

## Defect 6 — Reporter ServiceAccount / RBAC Binding

**Symptom**

The Reporter was unable to access the Kubernetes resources required by the application.

**Cause**

The RoleBinding referenced the wrong ServiceAccount. It was bound to the `default` ServiceAccount instead of the `reporter` ServiceAccount.

**Fix**

Changed the RoleBinding to use:

```yaml
subjects:
  - kind: ServiceAccount
    name: reporter
    namespace: debug-lab
```

**How I found it**

Inspected the Reporter workload:

```bash
kubectl describe pod <pod-name> -n debug-lab
kubectl describe deployment <deployment-name> -n debug-lab
```

I then checked the ServiceAccount authorization:

```bash
kubectl auth can-i list pods \
  -n debug-lab \
  --as=system:serviceaccount:debug-lab:reporter
```

**Verification**

Confirmed the Reporter ServiceAccount had the required permission:

```text
yes
```

I also verified the RoleBinding:

```bash
kubectl get rolebinding -n debug-lab
kubectl describe rolebinding <rolebinding-name> -n debug-lab
```

The binding now references the `reporter` ServiceAccount.

> **Note:** The RBAC fix was verified successfully, but the Reporter continued to have a separate application-level readiness problem. That unresolved issue is documented below rather than being presented as fixed by the RBAC change.

---

# Unresolved Finding — Reporter Application

After fixing the RBAC configuration, the Reporter still did not become Ready. I continued investigating this separately rather than treating it as another defect.

### Symptom

The Reporter Pod remained:

```text
READY   0/1
STATUS  Running
RESTARTS 0
```

The readiness probe repeatedly returned HTTP `503`:

```text
Readiness probe failed: HTTP probe failed with statuscode: 503
```

Because the Pod was not Ready, the Reporter Service had no endpoints.

```bash
kubectl get endpoints reporter -n debug-lab
```

returned an empty endpoint list.

Consequently:

```bash
wget -S -O- http://reporter:8080/report
```

returned:

```text
connection refused
```

### Investigation

Reporter logs showed:

```text
pod list failed: parse pod list: unexpected end of JSON input
```

I verified:

* Reporter Service exists on port `8080`.
* Reporter Pod is running and the application listens on port `8081`.
* Readiness probe targets `/healthz` on port `8081`.
* Reporter uses the `debug-lab/reporter` ServiceAccount.
* RBAC allows the Reporter ServiceAccount to list Pods.
* Backend connectivity works from inside the cluster.
* Gateway connectivity to the backend works.
* Kubernetes DNS resolution works for the backend.

From a temporary BusyBox Pod inside the cluster:

```text
backend:8080/healthz
→ HTTP 200 OK
```

```text
gateway.debug-lab.svc/status
→ HTTP 200 OK
→ backend: "ok"
```

```text
reporter:8080/report
→ connection refused
```

### Conclusion

The remaining Reporter issue was narrowed down to the **Reporter application's interaction with the Kubernetes API / Pod-list response**.

RBAC, Service configuration, backend connectivity, and cluster DNS were checked and did not explain the failure. The application reported:

```text
unexpected end of JSON input
```

when processing the Pod-list operation.

I could not conclusively establish the final root cause within the available investigation time, so I have documented this as an **unresolved finding rather than claiming a fix without sufficient evidence**.

