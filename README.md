# Terraform CI/CD Validation and Security Pipeline

A GitHub Actions pipeline that checks Terraform infrastructure code on every pull request and blocks merges when critical issues are found. It catches configuration errors, security misconfigurations, and risky deployment changes **before** they reach AWS.

> All infrastructure in this repository is **synthetic** and is never deployed to a real AWS account.

## What the pipeline checks

| Stage | Tool | Catches |
|---|---|---|
| Formatting | `terraform fmt -check` | Inconsistent formatting |
| Initialization | `terraform init -backend=false` | Setup problems, without touching real state |
| Validation | `terraform validate` | Syntax and configuration errors |
| Linting | TFLint (AWS ruleset) | AWS-specific mistakes, deprecated syntax |
| Security scanning | Checkov / Trivy | Security misconfigurations |
| Dependency review | Lock file + version pinning | Unpinned or risky providers and modules |
| Reporting | PR comments + GitHub Security tab | Makes findings visible before merge |

## Failure policy

_To be completed: which findings block a merge and which are warnings._

## Synthetic architecture

_To be completed: API Gateway, Lambda, S3, PostgreSQL._

## Demonstration

1. Clean configuration passes all checks
2. Intentional misconfiguration is flagged and the merge is blocked
3. Corrected configuration passes again

_Links to the demo pull requests will be added here._

## Repository structure

```
.github/workflows/   CI/CD pipeline
terraform/           Synthetic AWS configuration
docs/                Architecture and integration document
```

## Architecture and integration

See [`docs/architecture.md`](docs/architecture.md).
