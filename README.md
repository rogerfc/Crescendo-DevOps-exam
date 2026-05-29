# Crescendo DevOps Exam

## Overview

Deploys [Magnolia CMS Community Edition](https://www.magnolia-cms.com/) on AWS as a demo environment, reachable end-to-end via a CloudFront URL.

**Stack:** AWS (VPC · EC2 · ALB · CloudFront) · Terraform · GitHub Actions · Nginx · Apache Tomcat · Magnolia CMS 6.2

This is a demo-grade setup — it prioritises clarity and reproducibility over production hardening.

---

## Architecture


```mermaid
graph TB
    Internet((Internet))

    subgraph CF["CloudFront"]
        CFD[Distribution]
    end

    Internet -->|HTTPS| CFD

    subgraph AWS["AWS · eu-west-1"]
        subgraph VPC["VPC 10.0.0.0/16"]
            IGW[Internet Gateway]

            subgraph Pub["Public Subnets · eu-west-1a · eu-west-1b"]
                NATGW[NAT Gateway]
                ALB[Application Load Balancer · HTTP :80]
            end

            subgraph PrivA["Private · eu-west-1a"]
                subgraph EC2["EC2"]
                    direction TB
                    Nginx["Nginx :80"]
                    Tomcat["Tomcat :8080"]
                    Magnolia["Magnolia CMS"]
                end
            end
        end

        SSM["SSM Session Manager"]
        S3State["S3 Terraform state"]
    end

    CFD -->|"HTTP :80 · SG: CloudFront IPs only"| ALB
    ALB --> Nginx
    Nginx -->|proxy_pass| Tomcat
    Tomcat --> Magnolia
    EC2 -.->|outbound via| NATGW
    NATGW -.-> IGW
    IGW -.-> Internet
    SSM -.->|shell access| EC2
```


---

## Design decisions

### General
- Scope limited to what the task requires — no over-engineering

### Infrastructure
- Terraform 1.15 — latest stable at time of writing
- Terraform state in S3 with native locking (`use_lockfile`) — simpler than DynamoDB, built into TF 1.10+
- Deployed in AWS eu-west-1
- ALB SG restricted to CloudFront IPs via AWS-managed prefix list — direct access to the ALB DNS is blocked at the network level
- Application accessible only via CloudFront
- EC2 access only via SSM Session Manager — no key pairs, no inbound SSH rule

### Application
- Amazon Linux 2023 AMI — current AWS standard; native SSM support out of the box
- Magnolia community demo bundle — includes Tomcat, no manual assembly required
- Magnolia runs as a systemd service under a dedicated unprivileged user
- EC2 instance treated as disposable — rebuilt from scratch on every `terraform apply`

### CI
- GitHub Actions authenticates to AWS via OIDC — no long-lived credentials stored in the repo
- Three workflows: PR checks, manual apply (Plan → approval → Apply), manual destroy (Plan → approval → Destroy)
- Apply and destroy require approval from a repository environment reviewer before running

## How to run

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `~> 1.15`
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials sufficient to run the bootstrap steps
- Write access to this GitHub repository

### 1. One-time bootstrap

Follow [`tf-bootstrap/tf-bootstrap.md`](tf-bootstrap/tf-bootstrap.md). This creates:

- S3 bucket for Terraform state (`rfirpo-crescendo-tfstate`)
- OIDC identity provider in IAM
- IAM role trusted by this repository (`rfirpo-crescendo-github-actions`)
- Repository secret `AWS_ROLE_ARN`

### 2. Create the GitHub deployment environment

In the repository: **Settings → Environments → New environment**

- Name: `production`
- Enable **Required reviewers** and add yourself

This is the approval gate between the Plan and Apply jobs.

### 3. Deploy via GitHub Actions (recommended)

1. Go to **Actions → Terraform Apply → Run workflow**
2. The **Plan** job runs automatically — output is posted to the job summary
3. Once Plan succeeds, a **Review deployments** prompt appears — inspect the plan and approve
4. The **Apply** job runs against the saved plan file

> Magnolia takes **3–5 minutes to fully initialise** after the instance is running. The ALB target will show `unhealthy` during startup and self-heal. Total time from `apply` to a working CloudFront URL: **~10–12 minutes**.

The CloudFront URL is printed at the end of the Apply job as a Terraform output.

### 4. Local deployment (alternative)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Requires AWS credentials locally (e.g. `aws sso login` or an access key with the same permissions as the CI role).

### Teardown

Run **Actions → Terraform Destroy → Run workflow**, review the destroy plan, and approve.

---

## Troubleshooting

### Bootstrap verification

```bash
# State bucket exists and versioning is enabled
aws s3api get-bucket-versioning \
  --bucket rfirpo-crescendo-tfstate \
  --region eu-west-1

# IAM role exists
aws iam get-role \
  --role-name rfirpo-crescendo-github-actions \
  --query "Role.Arn" --output text
```

### ALB target health

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName,'rfirpo-crescendo')].TargetGroupArn" \
  --output text --region eu-west-1)

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region eu-west-1
```

Expected: `"State": "healthy"`. If `initial`, Magnolia is still starting — wait and retry.

### EC2 and application (via SSM)

```bash
# Get the instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=rfirpo-crescendo-magnolia" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region eu-west-1)

# Open a shell (no SSH key needed)
aws ssm start-session --target "$INSTANCE_ID" --region eu-west-1
```

Once connected:

```bash
# Bootstrap script output (check for errors during user_data)
sudo cat /var/log/user-data.log

# Magnolia service status
systemctl status magnolia

# Live Magnolia log — startup takes 3–5 min on first boot
sudo journalctl -u magnolia -f

# Nginx status
systemctl status nginx

# Verify Nginx → Tomcat locally (bypasses ALB and CloudFront)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/
# Expected: 200
```

### End-to-end

```bash
cd terraform && terraform output cloudfront_url
```

Open the URL in a browser. Expected: Magnolia login page.  
Default credentials: `superuser` / `superuser`

The first page load after a cold start may be slow (Tomcat JSP compilation).

---

## Assumptions
- Scope is a single-environment demo deployment; production readiness is explicitly out of scope
- Having the application load and respond is the acceptance criterion

## Known limitations
- Minimal security posture — a dev instance exposed to the internet via CloudFront
- Not dimensioned for any workload beyond demonstrating the application running
- No HA or horizontal scalability
- No persistent storage — disk and database content are ephemeral
- No centralised user directory
- No secrets management — only the default `superuser` credential is in use
- No distinct Author / Publisher instance topology
- No protection against application-level attacks (DDoS, etc.)
- No observability — no centralised log collection, no metrics, no alerting or monitoring
- EC2 instance is rebuilt from scratch on every change — no AMI baking or in-place update mechanism
- Some values are hardcoded (GitHub username, project prefix) — deployment elsewhere requires manual edits
- CI workflows are scoped to the repository owner; other contributors cannot trigger apply or destroy
- GHA SDLC coverage is minimal — no automated testing, no staging environment

## Disclaimer
This code has been written with assistance from Anthropic's GenAI models.
