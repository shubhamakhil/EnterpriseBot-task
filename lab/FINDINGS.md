
## Defect 1

**Symptom**  
Warning  Unhealthy  1s (x9 over 41s)  kubeletcReadiness probe failed: Get "http://10.244.0.126:8080/healthz": dial tcp 10.244.0.126:8080: connect: connection refused
the deploymentlog message literally said: listening on :8081 (image default is 8081; set PORT to override:

**Cause**  
was consuming port 8080:

**Fix**  
changed to 8081:

**How I found it**  
all pods were in pending state - kubectl get pods -n debug-lab:

described the pod : kubectl describe pod/pod-name -n debug-lab

described the deployment: kubectl describe deploy/name  -n debug-lab  

---

## Defect 2

**Symptom:**

Error: container has runAsNonRoot and image has non-numeric user (nonroot), cannot verify user is non-root 

**Cause:**

Instead of default administrative privileges (root, which is user ID 0), the container processes are restricted to the user ID (UID) 65532.

**Fix:**

added runAsUser: 65532 means the container will run as a specific, non-root user account inside container

**How I found it:**

described the pod : kubectl describe pod/pod-name -n debug-lab

described the deployment: kubectl describe deploy/name  -n debug-lab

---

## Defect 3

**Symptom:**

migrate job was not ready 

**Cause:**

Job.batch "migrate" is invalid: spec.template.spec.restartPolicy: Required value: valid values: "OnFailure", "Never"

**Fix:**

added : restartPolicy : OnFailure 

**How I found it:**

described the pod : kubectl describe pod/pod-name -n debug-lab

described the deployment: kubectl describe deploy/name  -n debug-lab


---

## Defect 4

**Symptom:**

the gateway service  was not ready  

**Cause:**

because the backed url was wrong
    BACKEND_URL: "http://backend.default.svc:8080"


**Fix:**

   BACKEND_URL: "http://backend.debug-lab.svc:8080"

**How I found it:**

described the pod : kubectl describe pod/pod-name -n debug-lab

described the deployment: kubectl describe deploy/name  -n debug-lab---

## Defect 5

**Symptom:**

the worker service was in false 

**Cause:**

FATAL: worker could not initialise its cache: mkdir /var/cache/app: read-only file system — the process needs a writable directory at /var/cache/app (mount a volume there, or set CACHE_DIR)


**Fix:**

adding: 

volumeMounts.name: worker-volume.mountPath: /var/cache/app 

**How I found it:**

described the pod : kubectl describe pod/pod-name -n debug-lab

described the deployment: kubectl describe deploy/name  -n debug-lab
## Defect 6

**Symptom:**

the reported  service was in false 

**Cause:**

showing 403 error 

**Fix:**

The role binding had wrong role reference as "default"  it should be reporter

**How I found it:**

described the pod : kubectl describe pod/pod-name -n debug-lab

described the deployment: kubectl describe deploy/name  -n debug-lab

---

If you ran out of time on any defect, say so here and describe what you would
have tried next — that section is read carefully and counts in your favour.

### Reporter — Unresolved Finding

**Symptom:**
The `reporter` Pod is running but remains `0/1 Ready`. Its readiness probe on `/healthz:8081` repeatedly returns HTTP `503`. Because the Pod is not Ready, the `reporter` Service has **no endpoints**, resulting in `connection refused` when accessing `reporter:8080/report`.

**What I checked:**

* Reporter Service exists on port `8080` with selector `app=reporter`.
* Reporter Pod is running with IP `10.244.0.103` and the application is listening on port `8081`.
* Pod events confirm repeated readiness probe failures with HTTP `503`.
* Reporter logs show:
  `pod list failed: parse pod list: unexpected end of JSON input`
* Verified the Reporter ServiceAccount is `debug-lab/reporter`.
* Verified RBAC using `kubectl auth can-i`; the Reporter ServiceAccount **can list Pods** in the namespace.
* From a temporary BusyBox Pod inside the cluster:

  * `backend:8080/healthz` → `200 OK`
  * `gateway.debug-lab.svc/status` → `200 OK` and reports `backend: "ok"`
  * `reporter:8080/report` → `connection refused`
  * Kubernetes DNS successfully resolves `backend`.

**Conclusion:**
The issue was narrowed down to the **Reporter application's interaction with the Kubernetes API / Pod-list response**. RBAC authorization, Service configuration, backend connectivity, and cluster DNS were verified and did not appear to be the cause.

The exact reason for the application's `unexpected end of JSON input` error could not be conclusively established within the available investigation time, so I have left this as an **unresolved finding rather than claiming a fix without sufficient evidence**.
