
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

The Reporter service throwing Readiness probe failed: HTTP probe failed with statuscode: 503

what i have checked so far :

1.) kubectl logs :-  pod list failed: parse pod list: unexpected end of JSON input

2.) checked SA  - correct SA attached

3.) kubectl auth can-i list pods ... --as=...reporter -- gives yes 