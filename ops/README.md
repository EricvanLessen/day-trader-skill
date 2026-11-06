# Rhodium Day Trader Monitor (experimental)

A small, **one-container** extension to the upstream `day-trader-skill` fork. All original `trader-*/SKILL.md` and Python scripts stay untouched.

- Original Yahoo/Nasdaq scanner: `daily` at 09:00 America/New_York and ORB at 10:00, 11:00, … 15:00 ET on weekdays. The upstream scanner handles NYSE closures and restricted ORB windows.
- Original news script checks up to five symbols (without SEC unless `SEC_USER_AGENT` is supplied).
- **Claude API** interprets original scanner/news results with the original scanner/news `SKILL.md` methodology. This is **not** a Claude Code CLI agent; it does not autonomously select or run other skills. The other nine original skills are preserved for future integration. No broker, no orders.
- One FastAPI worker with SSE live feed and two manual scan buttons. Optional browser notifications work while the page is open; no true Web Push in a closed browser. No React or database.
- SSE history and scanner files are ephemeral (lost on pod restart). No persistent trade records.

## Local test

Use Python 3.11+ and an Anthropic **API key**; a Claude chat subscription alone does not cover API usage.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements-monitor.txt
export ANTHROPIC_API_KEY='...'  # keep out of Git
export TRADER_DATA_DIR="$PWD/.trader-runtime"
uvicorn ops.web.app:app --host 127.0.0.1 --port 8080
```

Open http://127.0.0.1:8080 and press **Daily scan**. The full-universe Yahoo scan may take minutes; the unofficial API can rate-limit or return partial results. The first run downloads the Nasdaq symbol directory. ORB only works on a live trading day after the opening range closes. The app calls Claude after a successful scan with hits.

Environment: `CLAUDE_MODEL` (default `claude-sonnet-4-5`), `CLAUDE_MAX_TOKENS` (1100), `CLAUDE_MAX_HITS` (12), `AUTO_SCAN` (`true`), `SCAN_TIMEOUT_SECONDS` (900), `SEC_USER_AGENT` (optional). Check model availability and quotas in Anthropic Console. Claude API and GKE/Cloud Build costs are additional.

## Existing GKE cluster: Terraform

Terraform in `terraform/` **uses your existing cluster**, never creates a new GKE cluster. It creates an Artifact Registry Docker repo, namespace, one Deployment and an internal ClusterIP Service. The API key is not stored in Terraform state. With no backend configured the state is local; consider your existing private remote-state backend.

1. Authenticate and fetch credentials:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT
gcloud container clusters get-credentials YOUR_CLUSTER --location YOUR_CLUSTER_LOCATION --project YOUR_PROJECT
```

2. Review and apply (the Pod will not become ready until the image and Secret are created):

```bash
cd terraform
terraform init
terraform plan -var='project_id=YOUR_PROJECT' -var='region=europe-west3' -var='cluster_name=YOUR_CLUSTER' -var='cluster_location=YOUR_CLUSTER_LOCATION'
terraform apply -var='project_id=YOUR_PROJECT' -var='region=europe-west3' -var='cluster_name=YOUR_CLUSTER' -var='cluster_location=YOUR_CLUSTER_LOCATION'
cd ..
```

If the `day-trader` Artifact Registry repo or namespace already exists, import it or select a different name. Your GKE nodes must have Artifact Registry read access. Cloud Build and GKE require suitable project permissions and outbound network access to Yahoo/Anthropic.

3. Build and push from the repo root (enable Cloud Build API if necessary):

```bash
gcloud builds submit --tag europe-west3-docker.pkg.dev/YOUR_PROJECT/day-trader/day-trader-monitor:v1 .
```

4. Add the API key **outside Terraform**, and restart the Pod:

```bash
kubectl -n rhodium-trading create secret generic day-trader-anthropic --from-literal=api-key="$ANTHROPIC_API_KEY"
kubectl -n rhodium-trading rollout restart deployment/day-trader-monitor
kubectl -n rhodium-trading rollout status deployment/day-trader-monitor
kubectl -n rhodium-trading port-forward svc/day-trader-monitor 8080:8080
```

Set `ANTHROPIC_API_KEY` in your local shell first; do not paste its value into GitHub. Open http://127.0.0.1:8080 in your browser. Restart after rotating the Secret.

**Security:** The manual-run HTTP endpoint is unauthenticated and costs API quota. Keep the Service **internal** and access via `kubectl port-forward`. Do not add public Ingress without authentication and rate limiting.

## Tests

```bash
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s ops/web -p 'test_*.py' -v
```
