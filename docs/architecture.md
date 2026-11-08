# Architecture and Integration

This document explains how the pipeline in this repository would integrate with an existing AWS and Terraform repository, how to manage Terraform state and deployment permissions securely, how the approach supports reliability and security, and which additional controls fit a healthcare platform.

The repository itself uses synthetic infrastructure only. Everything below describes how the same approach would apply to a real environment.

## 1. Integrating with an existing repository

### Start by making `main` match what's deployed

The pipeline checks the code in pull requests to `main`. That only protects production if `main` actually describes what's running. If live infrastructure was applied from a branch that hasn't been merged, or changes were made outside Terraform, the first step is to reconcile them:

1. Review and merge the branch that was used for the live apply.
2. Run `terraform plan` against each environment's real state.
3. Confirm the plan shows **no changes**. Any differences mean the code and the live infrastructure disagree, and they need to be resolved before the pipeline can be trusted.

From then on, every change reaches the infrastructure only through a reviewed pull request to `main`.

### Roll out in phases

Turning on strict enforcement against code that hasn't been reviewed would block every pull request at once. A phased rollout avoids that:

| Phase | What happens |
|---|---|
| **1. Warn mode** | Run the pipeline with `SECURITY_ENFORCEMENT=warn`. Every finding is reported, nothing is blocked. |
| **2. Triage** | Fix real findings. Document genuine false positives as exceptions, with a written reason in the code. |
| **3. Enforce** | Switch to `enforce` and make the four checks required in branch protection. |
| **4. CI-driven deployment** | Move `plan` and `apply` into CI (section 2), so no one applies from a laptop. |

### Multiple modules and environments

The pipeline already supports a repository made of a root module and several child modules:

- `terraform fmt -check -recursive` checks formatting in every module.
- `terraform validate` on the root module also validates every child module it calls.
- `tflint --recursive` lints each module directory with the same configuration.
- Trivy and Checkov scan the whole directory tree, so findings in any module are reported with their file and line.

For per-environment variable files (for example, `staging.tfvars` and `production.tfvars`), the security scan can run once per environment using a matrix, passing each file with Trivy's `--tf-vars` option. This matters when environments differ, for example when production enables a setting that staging doesn't, so a scan with only the defaults would miss it.

One detail to watch: if the workflow only runs when certain paths change, a pull request that touches none of them never produces the required checks, and branch protection blocks it forever. Either run the workflow on every pull request, which is what this repository does, or add a lightweight job that always reports success when no Terraform files changed.

## 2. Running plan and apply from CI

Applying Terraform from a laptop means changes depend on one person's local setup and credentials, and nothing records exactly what was applied. Moving `plan` and `apply` into CI fixes both.

### Proposed workflow

1. **Pull request:** the existing checks run, plus `terraform plan` for each environment using a read-only role. The plan summary is posted to the pull request, so reviewers see exactly what will change.
2. **Destructive change check:** the plan is converted to JSON (`terraform show -json`) and checked for any resource that would be deleted or replaced. A replacement of a database or storage bucket blocks the pull request until someone with the right permissions explicitly approves it.
3. **Merge to `main`:** CI applies to **staging** automatically.
4. **Production:** the apply runs in a protected GitHub Environment that requires approval from a designated reviewer. It applies the plan generated from the same commit, so what was reviewed is what gets applied.
5. **One apply at a time:** a concurrency group per environment prevents two applies from running together, on top of Terraform's own state locking.

Example of the destructive change check:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json

jq -r '.resource_changes[]
       | select(.change.actions | index("delete"))
       | "\(.address): \(.change.actions | join(", "))"' plan.json
```

Any output means the plan deletes or replaces something, and the job fails until the change is approved.

## 3. Managing state and deployment permissions securely

### No long-lived AWS keys in CI

GitHub Actions should authenticate to AWS with **OIDC**, not stored access keys. GitHub issues a short-lived token for each run, and AWS exchanges it for temporary credentials. There are no keys to leak or rotate.

Each role's trust policy limits *which* workflow can use it:

| Role | Can be used by | Permissions |
|---|---|---|
| **Plan role** | Pull requests in this repository | Read-only access to AWS resources, read access to state, write access only to the lock |
| **Apply role** | Only the protected production environment (`sub: repo:<org>/<repo>:environment:production`) | Only what Terraform needs to manage the platform's resources |

Separate roles mean a pull request, even a malicious one, can never change infrastructure. Only an approved run in the protected environment can.

### Protecting the state bucket

Terraform state can contain sensitive values, such as resource identifiers and sometimes secrets, so the state bucket should be treated like patient data:

- **Encrypted** with a dedicated KMS key
- **Versioned,** so a corrupted or overwritten state can be recovered
- **Public access fully blocked,** with a bucket policy that denies non-HTTPS requests
- **Restricted** to the plan role, the apply role, and a monitored break-glass admin role
- **Access logged,** so every read and write of the state is recorded
- **Separate state per environment,** ideally in separate AWS accounts, so a mistake in staging can't affect production

Locking prevents two runs from changing state at the same time. Newer Terraform versions can lock directly in S3 (`use_lockfile = true`), which removes the need for a separate DynamoDB lock table. Either option works as long as locking is on.

### Drift detection

Drift happens when the live infrastructure no longer matches the code, for example after a console change during an incident. A scheduled workflow, nightly for example, can detect it:

```bash
terraform plan -detailed-exitcode
```

Exit code `2` means the plan found changes, so the live infrastructure has drifted. The workflow then opens an issue or sends an alert with the plan output. This uses the read-only plan role, so drift detection can never change anything. It's especially useful while moving from manual applies to CI, when drift is most likely.

## 4. How this supports reliability and security

- **Problems are caught before they reach AWS.** Formatting, validation, linting, scanning, and safety tests all run before merge, when fixes are cheapest.
- **Every change is reviewable.** The PR summary shows results without opening logs, and the plan shows exactly what will change.
- **Every exception is explained.** Skipped findings live in the code with a written reason, so they're reviewed like any other change instead of being silently ignored.
- **There's an audit trail.** Every infrastructure change maps to a pull request, a reviewer, and a CI run.
- **Results are reproducible.** Pinned tool versions, a committed lock file, and SHA-pinned actions mean the same code produces the same result every time.
- **Layers cover each other's gaps.** As the demonstrations show, each check catches something at least one other tool misses.

## 5. Additional controls for a healthcare platform

### Encryption at rest and in transit

- Customer-managed KMS keys for patient data stores, with rotation on and key usage logged in CloudTrail
- TLS enforced everywhere: `rds.force_ssl` on databases, HTTPS-only bucket policies, and modern TLS policies on load balancers
- Encryption also covering backups, snapshots, logs, container images, and Terraform state

### Audit logging

- An organization-wide CloudTrail trail with log file validation, encrypted with KMS, delivered to a separate log archive account that application teams can't modify
- CloudTrail data events for buckets holding patient documents, which record every object read and write. Unlike S3 server access logs, these can be KMS-encrypted.
- VPC flow logs, load balancer access logs, and database connection logs, kept long enough to meet the organization's retention requirements

### Backup and restore checks

A backup that has never been restored is not a tested backup.

- AWS Backup plans for databases and storage, with a vault lock so backups can't be deleted early, and copies to a second region or account
- **Scheduled restore tests:** regularly restore the latest backup into an isolated environment and verify it automatically, for example that the database starts and key tables contain data
- Documented recovery point and recovery time objectives, with the restore tests confirming they're actually met
- Deployment safety tests, like the ones in this repository, that fail if a change reduces backup retention or removes a backup plan

### Monitoring and alerting

- CloudWatch alarms for the signals that matter: database CPU, storage, and connections; container task health; load balancer 5xx errors; Lambda errors and throttles
- GuardDuty for threat detection, and Security Hub to collect findings in one place
- AWS Config rules, including the HIPAA conformance pack, to continuously check that resources stay compliant after deployment, not just at merge time
- Alarms defined in Terraform and covered by safety tests, so removing an alarm is caught in review
- Alerts routed to an on-call channel with a runbook for each one

### Access and compliance

- Human access through IAM Identity Center with MFA, no long-lived IAM user keys, and a monitored break-glass procedure
- Only HIPAA-eligible AWS services used for patient data, under a Business Associate Agreement with AWS
- Logs that never contain patient data: the API and Lambda in this repository log request metadata only, never request bodies

Compliance involves policies, training, and agreements beyond infrastructure. This pipeline provides technical evidence for part of it: every infrastructure change is reviewed, scanned, tested, and recorded.

## 6. Limitations and next steps

Being clear about what this pipeline doesn't do yet:

- **Static checks only.** The pipeline reads code. It can't see the live environment until plan-based checks and drift detection (sections 2 and 3) are added with real AWS access.
- **Scanners have gaps.** I found that Trivy didn't flag wildcard IAM role policies, which is why Checkov covers IAM. Scanner behavior can change between versions, so a useful next step is a folder of known-bad test configurations that CI scans on every run, failing if any of them is *not* caught. That would detect scanner regressions after upgrades.
- **The medium-severity rule uses keywords.** Medium findings block based on words in the finding's title (encryption, public, IAM, logging). This is simple and transparent, but an explicit list of blocking check IDs would be more precise as the rule set grows.
- **Checkov runs IAM checks only.** That's deliberate, to avoid duplicating Trivy, but more Checkov checks could be added where they cover other gaps.
