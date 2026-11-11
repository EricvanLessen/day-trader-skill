# Rhodium Day Trader Monitor

The deployed MVP is **read-only monitoring**: Nasdaq Trader universe -> Yahoo
scanner -> news check -> Anthropic Claude -> FastAPI/SSE browser feed. The
monitor has no broker connection and does not execute orders. The original
skills remain unchanged; Claude receives the scanner and news skill guidance,
not tools to run them.

## Deployment and prerequisites

- GCP project `arctic-conduit-384012`; existing GKE cluster
  `rhodium-silent-funded`, zone `europe-west3-a`.
- Namespace `rhodium-trading`; Deployment and internal ClusterIP Service
  `day-trader-monitor`.
- Deployed image:
  `europe-west3-docker.pkg.dev/arctic-conduit-384012/day-trader/day-trader-monitor:v4`.
- Install Google Cloud CLI (including the GKE auth plugin), `kubectl`, Terraform
  >= 1.6 and `curl`. You need project/cluster permissions, the existing
  Terraform state and an Anthropic API key with model access. Nodes need
  Artifact Registry read access and outbound access to Yahoo and Anthropic.
- The key is supplied through Kubernetes Secret `day-trader-anthropic`, key
  `api-key`, not through Terraform. Never commit secrets, `.tfvars`, Terraform
  state or generated files. Protect local state; no backend is configured here.

Authenticate both the CLI and Terraform's Application Default Credentials
(ADC), then select the cluster:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project arctic-conduit-384012
gcloud container clusters get-credentials rhodium-silent-funded \
  --zone europe-west3-a --project arctic-conduit-384012
```

Terraform uses the existing cluster; it manages the registry repository,
namespace, Deployment and Service, not the cluster. From the repository root,
use the existing state and review the plan before applying:

```bash
cd terraform
terraform init
terraform plan -var='project_id=arctic-conduit-384012' \
  -var='region=europe-west3' -var='cluster_name=rhodium-silent-funded' \
  -var='cluster_location=europe-west3-a' -var='image_tag=v4' \
  -var='claude_model=claude-sonnet-5-5'
terraform apply -var='project_id=arctic-conduit-384012' \
  -var='region=europe-west3' -var='cluster_name=rhodium-silent-funded' \
  -var='cluster_location=europe-west3-a' -var='image_tag=v4' \
  -var='claude_model=claude-sonnet-5-5'
cd ..
```

The explicit image and model overrides matter: Terraform's defaults are `v1`
and `claude-sonnet-4-5`. Terraform also loads local variable files; check the
entire plan for unintended changes, including `auto_scan`, before applying. Do
not apply against a fresh state as if it were the existing deployment; import
existing resources into the correct state if necessary.

## Operate

Verify rollout, pods and both configured image and pulled image digest:

```bash
kubectl -n rhodium-trading rollout status deployment/day-trader-monitor
kubectl -n rhodium-trading get pods -l app=day-trader-monitor \
  -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID'
kubectl -n rhodium-trading get deployment day-trader-monitor \
  -o 'jsonpath={.spec.template.spec.containers[0].image}{"\n"}'
```

Connect and leave this command running:

```bash
kubectl -n rhodium-trading port-forward svc/day-trader-monitor 8080:8080
```

Open http://localhost:8080 and use **Daily scan** or **ORB scan**. Alternatively,
in another terminal, run one scan at a time:

```bash
curl -sS -X POST 'http://localhost:8080/api/run?mode=daily'
curl -sS -X POST 'http://localhost:8080/api/run?mode=orb'
```

Wait for the first scan to finish before starting the second; concurrent
requests return HTTP 409. A full-universe scan can take minutes. ORB requires
a live trading day after the opening range closes. With `AUTO_SCAN=true`, daily
scans are scheduled at 09:00 and ORB scans hourly from 10:00 through 15:00
America/New_York on weekdays; upstream checks holidays and ORB windows.

Inspect the live SSE stream in a separate terminal (Ctrl-C to disconnect), and
the application logs:

```bash
curl -N http://localhost:8080/api/events
kubectl -n rhodium-trading logs deployment/day-trader-monitor --tail=200 -f
```

Look for `analysis_start`, `analysis_final` or `error`, and `done`. Final
analysis and empty-response errors carry Claude metadata; logs include
`Claude response metadata`. A tested response reported
`stop_reason=end_turn`, `input_tokens=13940`, `output_tokens=3133`, and
`content_types=['thinking','text']`. These are observations from that run,
not guaranteed values for future runs. SSE history and scanner files are
ephemeral and disappear on pod restart.

Stop and start the monitor:

```bash
kubectl -n rhodium-trading scale deployment/day-trader-monitor --replicas=0
kubectl -n rhodium-trading scale deployment/day-trader-monitor --replicas=1
kubectl -n rhodium-trading rollout status deployment/day-trader-monitor
```

Terraform declares **one replica**; a later `terraform apply` can undo the
manual scale-to-zero and restart the service. Scaling the pod down does **not**
stop the existing GKE cluster or its costs. Claude API and other GCP usage can
also incur charges.

## Configuration and limitations

`CLAUDE_MODEL` must name an API-accessible model for the Anthropic account;
the currently deployed choice is `claude-sonnet-5-5`. The application defaults
`CLAUDE_MAX_TOKENS` to 4096 and `CLAUDE_MAX_HITS` to 12. Terraform explicitly
sets the model and `AUTO_SCAN` (default `true`); a Terraform model override
takes precedence over the application default. `SCAN_TIMEOUT_SECONDS` defaults
to 900. `SEC_USER_AGENT` is optional; without it the monitor skips SEC news.
An Anthropic API key is required; a Claude chat subscription alone is not an
API key.

- Claude sees at most 12 scan hits by default, even when the scan finds more.
  The news check covers at most five symbols, and its input to Claude is
  truncated to 12,000 characters; upstream news can be incomplete or low
  quality. A full Claude response does **not** mean its upstream news input was
  complete or verified.
- Yahoo data comes from an unofficial API and may be rate-limited or partial.
  The first scan downloads the Nasdaq symbol directory.
- Access is manual via port-forward. The run endpoint is unauthenticated and
  consumes API quota; keep the Service internal and do not expose it publicly
  without authentication and rate limiting. Browser notifications require an
  open page; they are not background Web Push.

## Troubleshooting

- **ADC `invalid_rapt`:** rerun `gcloud auth application-default login`,
  then retry Terraform. If CLI authentication also expired, rerun
  `gcloud auth login` and get cluster credentials again.
- **Local port 8080 in use:** stop the process using it, or run
  `kubectl -n rhodium-trading port-forward svc/day-trader-monitor 8081:8080`
  and use http://localhost:8081 instead.
- **Wrong image or code:** compare the Deployment image and pod `IMAGE_ID`
  above; inspect the actual running image's code, not just the local checkout:

  ```bash
  kubectl -n rhodium-trading exec deployment/day-trader-monitor -- \
    grep -nE 'get_final_message|Claude response metadata|CLAUDE_MAX_TOKENS' /app/ops/web/app.py
  ```

- **Empty Claude response:** inspect SSE `error` and log metadata, especially
  `stop_reason`, token counts and `content_types`. Thinking consumes output
  tokens; a `max_tokens` stop without a text block can require a larger
  `CLAUDE_MAX_TOKENS`. Check API model access, errors and scan/news warnings
  too. An `end_turn` with visible text is a completed Claude response, not
  proof of complete source data.

## Rhodium quickstart: directly to GKE

**This is the only path you need for the Rhodium service.** Do **not** follow the upstream Claude plugin instructions from the root README, do **not** copy the skills manually, and do **not** install React. The repository already includes the original skills and the `Dockerfile`.

**Prerequisites:** An existing GKE cluster; local `git`, `gcloud`, `kubectl` and `terraform` installed; Google Cloud permissions for Cloud Build, Artifact Registry and Kubernetes; a separately billed Anthropic API key. No GCP credentials or API keys belong in Git.

**1. Clone your fork (run in your local terminal):**

```bash
git clone https://github.com/EricvanLessen/day-trader-skill.git
cd day-trader-skill
git switch main
git pull --ff-only
```

**2. Authenticate to your existing GKE cluster:**

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
gcloud container clusters get-credentials YOUR_CLUSTER_NAME --location YOUR_CLUSTER_LOCATION --project YOUR_PROJECT_ID
```

**3. Create a local Terraform configuration (this is ignored by Git):**

```bash
cat > terraform/terraform.tfvars <<'EOF'
project_id       = "YOUR_PROJECT_ID"
region           = "europe-west3"
cluster_name     = "YOUR_CLUSTER_NAME"
cluster_location = "YOUR_CLUSTER_LOCATION"
EOF
```

Adjust `region` to the Artifact Registry region you want and `cluster_location` to the **actual** GKE cluster location (zone or region).

**4. Review and create the resources:**

```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
cd ..
```

Terraform adds an Artifact Registry repository, a namespace, one Deployment and an **internal-only** Kubernetes Service to your **existing** cluster. **It does not create GKE.** The Pod may initially be unhealthy: the image and Kubernetes Secret do not exist yet. This is expected during the first bootstrap.

**5. Build/push the container, then provide the Anthropic key via a Kubernetes Secret:**

```bash
gcloud builds submit --tag europe-west3-docker.pkg.dev/YOUR_PROJECT_ID/day-trader/day-trader-monitor:v1 .
read -rsp 'Anthropic API key: ' ANTHROPIC_API_KEY; echo
kubectl -n rhodium-trading create secret generic day-trader-anthropic --from-literal=api-key="$ANTHROPIC_API_KEY"
unset ANTHROPIC_API_KEY
kubectl -n rhodium-trading rollout restart deployment/day-trader-monitor
kubectl -n rhodium-trading rollout status deployment/day-trader-monitor
```

If you chose a different Artifact Registry `region`, substitute that region in the `gcloud builds submit --tag` image URI too. Ensure the image is accessible to your GKE nodes. For an existing Secret, update it instead of running `create` again.

**6. Open the browser feed (keep this terminal open):**

```bash
kubectl -n rhodium-trading port-forward svc/day-trader-monitor 8080:8080
```

Open **http://127.0.0.1:8080**. You can manually trigger `Daily scan` or `ORB scan`. Scheduled scans run automatically when enabled. This is an internal monitor: do **not** expose it publicly without authentication.

**Optional, not part of deployment:** Run the local Python tests below if you want a preflight check. No local Python environment is required to deploy the container.

## Local test

Use Python 3.11+ and run from the repository root:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements-monitor.txt
export ANTHROPIC_API_KEY='...'  # keep out of Git
export TRADER_DATA_DIR="$PWD/.trader-runtime"
uvicorn ops.web.app:app --host 127.0.0.1 --port 8080
```

Open http://localhost:8080. Offline tests:

```bash
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s ops/web -p 'test_*.py' -v
```
