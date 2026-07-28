#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: extract-ci-failures.sh [--repo OWNER/REPO] [--max-jobs N] [--max-lines N] [--max-bytes N] RUN_ID_OR_URL

Print bounded diagnostics for failed jobs in a GitHub Actions run.
EOF
}

repo=
run=
max_jobs=${CI_FAILURE_MAX_JOBS:-3}
max_lines=${CI_FAILURE_MAX_LINES:-120}
max_bytes=${CI_FAILURE_MAX_BYTES:-30000}

while (($#)); do
  case "$1" in
    --repo)
      repo=${2:?--repo requires OWNER/REPO}
      shift 2
      ;;
    --max-jobs)
      max_jobs=${2:?--max-jobs requires a number}
      shift 2
      ;;
    --max-lines)
      max_lines=${2:?--max-lines requires a number}
      shift 2
      ;;
    --max-bytes)
      max_bytes=${2:?--max-bytes requires a number}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$run" ]]; then
        echo "only one run ID or URL may be supplied" >&2
        exit 2
      fi
      run=$1
      shift
      ;;
  esac
done

[[ -n "$run" ]] || {
  usage >&2
  exit 2
}
for value in "$max_jobs" "$max_lines" "$max_bytes"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
    echo "limits must be positive integers" >&2
    exit 2
  }
done

if [[ "$run" == http://* || "$run" == https://* ]]; then
  if [[ "$run" =~ /actions/runs/([0-9]+) ]]; then
    run=${BASH_REMATCH[1]}
  else
    echo "URL does not contain a GitHub Actions run ID" >&2
    exit 2
  fi
fi
[[ "$run" =~ ^[0-9]+$ ]] || {
  echo "run must be a numeric GitHub Actions run ID or URL" >&2
  exit 2
}

if [[ -z "$repo" ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
report=$work/report
jobs=$work/jobs

{
  gh run view "$run" --repo "$repo" \
    --json name,displayTitle,status,conclusion,url \
    --jq '"Run: \(.displayTitle // .name)\nStatus: \(.status) / \(.conclusion // "pending")\nURL: \(.url)"'
  echo

  gh api --paginate "repos/$repo/actions/runs/$run/jobs?per_page=100" \
    --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure" or .conclusion == "action_required" or .conclusion == "stale") | [.id, .name, .conclusion, .html_url] | @tsv' \
    > "$jobs"

  if [[ ! -s "$jobs" ]]; then
    echo "No failed job logs are available. Inspect the run URL for a workflow-level or startup failure."
  else
    job_count=0
    while IFS=$'\t' read -r job_id job_name conclusion job_url; do
      ((job_count += 1))
      if ((job_count > max_jobs)); then
        remaining=$(($(wc -l < "$jobs") - max_jobs))
        printf '\n[%d additional failed job(s) omitted]\n' "$remaining"
        break
      fi

      printf '%s\n' "== $job_name ($conclusion) ==" "Job: $job_url"
      failed_steps=$(gh api "repos/$repo/actions/jobs/$job_id" \
        --jq '[.steps[]? | select(.conclusion == "failure" or .conclusion == "timed_out") | .name] | join(", ")' 2>/dev/null || true)
      [[ -z "$failed_steps" ]] || printf 'Failed steps: %s\n' "$failed_steps"

      log=$work/job-$job_id.log
      if ! gh run view "$run" --repo "$repo" --job "$job_id" --log-failed > "$log" 2>&1; then
        echo "Failed-step logs were unavailable."
      elif [[ ! -s "$log" ]]; then
        echo "Failed-step logs were empty."
      else
        lines=$(wc -l < "$log" | tr -d ' ')
        if ((lines <= max_lines)); then
          cat "$log"
        else
          first=$((max_lines / 3))
          ((first > 0)) || first=1
          last=$((max_lines - first))
          head -n "$first" "$log"
          printf '[%d log lines omitted]\n' "$((lines - max_lines))"
          tail -n "$last" "$log"
        fi
      fi
      echo
    done < "$jobs"
  fi
} > "$report" 2>&1

bytes=$(wc -c < "$report" | tr -d ' ')
if ((bytes <= max_bytes)); then
  cat "$report"
else
  head -c "$max_bytes" "$report"
  printf '\n[%d bytes omitted; open the run URL for full logs]\n' "$((bytes - max_bytes))"
fi
