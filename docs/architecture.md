# Architecture and Integration

How this pipeline would plug into an existing AWS and Terraform repository, how to secure state and deployment permissions, and which additional controls fit a healthcare platform. The repository itself uses synthetic infrastructure only.

## Summary

- **Integration:** first make `main` match what's deployed, then roll out in phases, starting in warn mode.
- **CI deployment:** plan on every pull request, block destructive changes without approval, require approval for production.
- **Permissions:** GitHub OIDC with separate read-only plan and scoped apply roles. No long-lived keys.
- **State:** encrypted, versioned, access-logged, locked, and separate per environment.
- **Drift:** a nightly read-only plan that alerts when live infrastructure no longer matches the code.
- **Healthcare controls:** encryption everywhere, central audit logging, tested backup restores, and monitoring with alerts.

## 1. Integrating with an existing repository

**Make `main` the source of truth first.** If live infrastructure was applied from an unmerged branch, merge it, run `terraform plan` against each environment, and confirm it shows no changes. From then on, changes reach infrastructure only through reviewed pull requests to `main`.

**Roll out in phases:**

1. **Warn mode** (`SECURITY_ENFORCEMENT=warn`): report findings on existing code without blocking.
2. **Triage:** fix real findings and document genuine exceptions with a reason.
3. **Enforce:** switch to `enforce` and make the checks required.
4. **CI-driven deployment:** move plan and apply into CI (section 2).

**Multiple modules and environments:** the pipeline already handles a root module with child modules. `fmt -recursive`, `validate` on the root, `tflint --recursive`, and both scanners cover every module. For per-environment variable files, the security scan can run once per environment using Trivy's `--tf-vars` option, so settings that differ in production are scanned too.

## 2. Running plan and apply from CI

1. **Pull request:** checks run, plus `terraform plan` per environment with a read-only role. The plan is posted to the pull request.
2. **Destructive change check:** the plan JSON is checked for anything deleted or replaced. Replacing a database or bucket needs explicit approval:

   ```bash
   terraform show -json tfplan | jq -r '.resource_changes[] | select(.change.actions | index("delete")) | .address'
   ```

3. **Merge:** CI applies to staging automatically.
4. **Production:** applies only in a protected GitHub Environment with required reviewers, using the plan from the same commit.
5. **One apply at a time** per environment, on top of Terraform's state locking.

## 3. State and deployment permissions

**OIDC instead of stored keys.** GitHub Actions gets short-lived AWS credentials for each run, so there are no keys to leak or rotate. Two roles, each limited by its trust policy:

| Role | Used by | Can do |
|---|---|---|
| Plan | Pull requests | Read resources and state, write the lock |
| Apply | Only the protected production environment | Manage the platform's resources |

A pull request, even a malicious one, can never change infrastructure.

**State bucket.** State can contain sensitive values, so treat it like patient data: KMS-encrypted, versioned, public access blocked, HTTPS-only, access-logged, and restricted to the two roles plus a monitored break-glass role. Keep state separate per environment, ideally in separate AWS accounts. Use locking, either DynamoDB or S3-native locking in newer Terraform versions.

**Drift detection.** A nightly workflow runs `terraform plan -detailed-exitcode` with the read-only role. Exit code `2` means live infrastructure has drifted from the code, and the workflow raises an alert. This matters most while moving from manual applies to CI.

## 4. How this supports reliability and security

- Problems are caught before they reach AWS, when fixes are cheapest.
- Every change is reviewed, scanned, tested, and traceable to a pull request.
- Exceptions are written down in the code instead of silently ignored.
- Pinned versions and a committed lock file make results reproducible.
- Each layer catches something another misses, as the demonstrations show.

## 5. Additional healthcare controls

- **Encryption:** customer-managed KMS keys for patient data, TLS enforced on every connection, and encrypted backups, logs, and state.
- **Audit logging:** an organization-wide CloudTrail trail in a separate log archive account, plus CloudTrail data events on buckets holding patient documents.
- **Backup and restore:** AWS Backup with a vault lock and cross-region copies, and scheduled restore tests that prove backups actually work.
- **Monitoring and alerting:** CloudWatch alarms on databases, services, and errors; GuardDuty, Security Hub, and the AWS Config HIPAA conformance pack, with alerts routed to on-call.
- **Access:** IAM Identity Center with MFA, no long-lived user keys, and HIPAA-eligible services under an AWS Business Associate Agreement.

## 6. Limitations and next steps

- **Static checks only.** Plan-based checks and drift detection need real AWS access, so they're described here rather than built.
- **Scanners have gaps.** Trivy missed wildcard IAM policies, so Checkov covers IAM. A next step is a folder of known-bad configurations that CI scans on every run, to catch scanner regressions after upgrades.
- **The medium-severity rule uses keywords.** An explicit list of blocking check IDs would be more precise as the rules grow.
