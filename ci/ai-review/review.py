#!/usr/bin/env python3
"""
AI pull/merge-request reviewer (Amazon Bedrock) — works on GitHub Actions
AND GitLab CI from one script.

Flow:
  1. Obtain AWS creds:
       - GitLab: exchange the job's OIDC id_token (GITLAB_OIDC_TOKEN) for
         short-lived creds via sts:AssumeRoleWithWebIdentity.
       - GitHub: rely on the standard boto3 credential chain — the workflow's
         aws-actions/configure-aws-credentials step (OIDC) has already exported
         creds into the environment.
  2. Fetch the PR/MR diff via the host API.
  3. Ground the model on repo context (ADRs / OPA policies / architecture, or
     whatever AI_REVIEW_CONTEXT_PATHS points at).
  4. Ask a Bedrock Claude model to review for security, IAM/IRSA scope,
     decision-record/policy conflicts, correctness, and ops risk.
  5. Post the findings as a PR/MR comment (soft gate).

Dependencies: boto3 + Python stdlib only.

Common env:
  AWS_REGION (default eu-central-1), BEDROCK_MODEL_ID,
  AI_REVIEW_BLOCK_ON_HIGH ("true" to exit 1 on a High/BLOCK verdict),
  AI_REVIEW_MAX_DIFF_CHARS, AI_REVIEW_MAX_CONTEXT_CHARS,
  AI_REVIEW_CONTEXT_PATHS (comma-separated dirs/files; overrides defaults).

GitLab: GITLAB_OIDC_TOKEN, AWS_ROLE_ARN, AI_REVIEW_GITLAB_TOKEN,
        plus predefined CI_API_V4_URL/CI_PROJECT_ID/CI_MERGE_REQUEST_IID/CI_PROJECT_DIR.
GitHub: GITHUB_TOKEN (pull-requests: write), plus predefined
        GITHUB_API_URL/GITHUB_REPOSITORY/GITHUB_EVENT_PATH/GITHUB_WORKSPACE.
"""
import json
import os
import sys
import urllib.error
import urllib.request

REGION = os.environ.get("AWS_REGION", "eu-central-1")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "eu.anthropic.claude-haiku-4-5-20251001-v1:0")
MAX_DIFF = int(os.environ.get("AI_REVIEW_MAX_DIFF_CHARS", "45000"))
MAX_CTX = int(os.environ.get("AI_REVIEW_MAX_CONTEXT_CHARS", "24000"))
BLOCK_ON_HIGH = os.environ.get("AI_REVIEW_BLOCK_ON_HIGH", "false").lower() == "true"

# Default grounding sources (relative to the repo root). Override per-repo with
# AI_REVIEW_CONTEXT_PATHS, e.g. "docs/adr,CONTRIBUTING.md,docs/security".
DEFAULT_CONTEXT_PATHS = ["docs/decisions", "policies/opa", "docs/ARCHITECTURE.md"]
CONTEXT_EXTS = (".md", ".rego", ".rst", ".txt")

SYSTEM_PROMPT = """\
You are a senior platform & cloud-security engineer reviewing a change request \
for a software repository (may include Terraform, Helm, application code, CI).

You are given:
  - PROJECT CONTEXT: the repo's own decision records, policies, and docs. Treat \
these as the project's binding rules.
  - DIFF: the unified diff for this pull/merge request.

Review ONLY what the diff changes. Do not invent issues or comment on code that \
is not in the diff. Be concrete and cite the file path.

Focus, in priority order:
  1. Security: IAM/IRSA scope (wildcards, over-broad Resource/Action), secrets \
in code, network exposure (0.0.0.0/0, public endpoints), disabled encryption/TLS, \
authz/input-validation gaps in application code.
  2. Decision-record / policy conflicts: anything that contradicts a stated ADR \
or policy (name it).
  3. Correctness: bugs, broken references, missing wiring.
  4. Operational risk: blast radius, irreversibility, missing tags/limits.

Output GitHub-flavored markdown ONLY, in this exact shape:

### 🤖 AI review summary
<one or two sentence verdict>

### Findings
For each finding, a bullet:
- <SEVERITY> **<short title>** — `<path>`: <what & why, cite ADR/policy if relevant>. \
_Suggested fix:_ <concise fix>

Use these severity tags verbatim: `🔴 High`, `🟠 Medium`, `🟡 Low`, `🟢 Nit`.
If there are no issues, write "No blocking issues found. 🟢" under Findings.

Keep it tight — at most ~12 findings, highest severity first. End with:

### Verdict
One of: `BLOCK` (a High issue), `COMMENT` (Medium/Low only), or `APPROVE` (clean).
"""


# --------------------------------------------------------------------------- #
# HTTP helper
# --------------------------------------------------------------------------- #
def http(method, url, headers, data=None, raw=False):
    body = None
    if data is not None:
        body = data if isinstance(data, (bytes, bytearray)) else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=30) as resp:
        text = resp.read().decode()
    return text if raw else json.loads(text)


# --------------------------------------------------------------------------- #
# Host platforms
# --------------------------------------------------------------------------- #
class GitLab:
    name = "gitlab"

    def __init__(self):
        self.api = os.environ["CI_API_V4_URL"].rstrip("/")
        self.pid = os.environ.get("CI_PROJECT_ID", "")
        self.iid = os.environ.get("CI_MERGE_REQUEST_IID", "")
        self.token = os.environ.get("AI_REVIEW_GITLAB_TOKEN", "")
        self.workspace = os.environ.get("CI_PROJECT_DIR", ".")

    def ready(self):
        return bool(self.iid)

    def _h(self):
        return {"PRIVATE-TOKEN": self.token, "Content-Type": "application/json"}

    def get_diff(self):
        res = http("GET", f"{self.api}/projects/{self.pid}/merge_requests/{self.iid}/changes", self._h())
        parts = []
        for ch in res.get("changes", []):
            parts.append(f"--- {ch.get('old_path')}\n+++ {ch.get('new_path')}\n" + (ch.get("diff") or ""))
        return res.get("title", ""), "\n".join(parts)

    def post_comment(self, body):
        http("POST", f"{self.api}/projects/{self.pid}/merge_requests/{self.iid}/notes",
             self._h(), {"body": body})


class GitHub:
    name = "github"

    def __init__(self):
        self.api = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
        self.repo = os.environ.get("GITHUB_REPOSITORY", "")
        self.token = os.environ.get("GITHUB_TOKEN", "")
        self.workspace = os.environ.get("GITHUB_WORKSPACE", ".")
        self.number, self.title = self._pr_from_event()

    def _pr_from_event(self):
        path = os.environ.get("GITHUB_EVENT_PATH")
        if path and os.path.isfile(path):
            ev = json.load(open(path, encoding="utf-8"))
            pr = ev.get("pull_request") or {}
            return pr.get("number") or ev.get("number"), pr.get("title", "")
        return None, ""

    def ready(self):
        return bool(self.number)

    def _h(self, accept="application/vnd.github+json"):
        return {"Authorization": f"Bearer {self.token}", "Accept": accept,
                "X-GitHub-Api-Version": "2022-11-28"}

    def get_diff(self):
        diff = http("GET", f"{self.api}/repos/{self.repo}/pulls/{self.number}",
                    self._h("application/vnd.github.diff"), raw=True)
        return self.title, diff

    def post_comment(self, body):
        http("POST", f"{self.api}/repos/{self.repo}/issues/{self.number}/comments",
             self._h(), {"body": body})


def detect_platform():
    if os.environ.get("GITHUB_ACTIONS") == "true":
        return GitHub()
    if os.environ.get("GITLAB_CI") == "true":
        return GitLab()
    # explicit fallback for local testing
    return GitHub() if os.environ.get("AI_REVIEW_PLATFORM") == "github" else GitLab()


# --------------------------------------------------------------------------- #
# Context, model, AWS
# --------------------------------------------------------------------------- #
def gather_context(root):
    paths = os.environ.get("AI_REVIEW_CONTEXT_PATHS")
    entries = [p.strip() for p in paths.split(",")] if paths else DEFAULT_CONTEXT_PATHS
    chunks, total = [], 0

    def add(rel, text):
        nonlocal total
        if total >= MAX_CTX or not text:
            return
        text = text[: max(0, MAX_CTX - total)]
        chunks.append(f"===== {rel} =====\n{text}")
        total += len(text)

    for entry in entries:
        full = os.path.join(root, entry)
        if os.path.isfile(full):
            try:
                add(entry, open(full, encoding="utf-8").read())
            except Exception:
                pass
        elif os.path.isdir(full):
            for name in sorted(os.listdir(full)):
                if not name.endswith(CONTEXT_EXTS):
                    continue
                fp = os.path.join(full, name)
                if os.path.isfile(fp):
                    try:
                        add(os.path.join(entry, name), open(fp, encoding="utf-8").read())
                    except Exception:
                        pass
                if total >= MAX_CTX:
                    break
        if total >= MAX_CTX:
            break
    return "\n\n".join(chunks)


def bedrock_client():
    """GitLab: exchange OIDC token for creds. GitHub/local: default chain."""
    import boto3
    token = os.environ.get("GITLAB_OIDC_TOKEN")
    role = os.environ.get("AWS_ROLE_ARN")
    if token and role:
        sts = boto3.client("sts", region_name=REGION)
        c = sts.assume_role_with_web_identity(
            RoleArn=role,
            RoleSessionName=f"ai-review-{os.environ.get('CI_PIPELINE_ID', 'local')}"[:64],
            WebIdentityToken=token,
            DurationSeconds=3600,
        )["Credentials"]
        return boto3.client("bedrock-runtime", region_name=REGION,
                            aws_access_key_id=c["AccessKeyId"],
                            aws_secret_access_key=c["SecretAccessKey"],
                            aws_session_token=c["SessionToken"])
    return boto3.client("bedrock-runtime", region_name=REGION)


def review(brt, title, diff, context):
    if len(diff) > MAX_DIFF:
        diff = diff[:MAX_DIFF] + "\n... [diff truncated for length] ...\n"
    user = (f"CHANGE REQUEST TITLE: {title}\n\n"
            f"PROJECT CONTEXT (decision records / policies / docs):\n{context}\n\n"
            f"DIFF:\n{diff}\n")
    resp = brt.converse(
        modelId=MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": user}]}],
        inferenceConfig={"maxTokens": 2000, "temperature": 0.0},
    )
    return resp["output"]["message"]["content"][0]["text"], resp.get("usage", {})


def main():
    host = detect_platform()
    if not host.ready():
        print(f"[{host.name}] Not a PR/MR pipeline; skipping AI review.")
        return 0

    title, diff = host.get_diff()
    if not diff.strip():
        print("Empty diff; nothing to review.")
        return 0
    context = gather_context(host.workspace)
    print(f"[{host.name}] Reviewing (diff {len(diff)} chars, context {len(context)} chars) with {MODEL_ID}")

    text, usage = review(bedrock_client(), title, diff, context)
    footer = (f"\n\n<sub>🤖 Generated by Amazon Bedrock (`{MODEL_ID}`, {REGION}) · "
              f"in:{usage.get('inputTokens', '?')} out:{usage.get('outputTokens', '?')} tokens · "
              f"advisory, not a merge gate</sub>")
    body = text + footer

    try:
        host.post_comment(body)
        print(f"[{host.name}] Posted AI review comment.")
    except urllib.error.HTTPError as e:
        print(f"[{host.name}] Failed to post comment ({e.code}); printing inline:\n{body}")

    if BLOCK_ON_HIGH and "🔴 High" in text and "BLOCK" in text.upper():
        print("High-severity BLOCK verdict; failing job (AI_REVIEW_BLOCK_ON_HIGH).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
