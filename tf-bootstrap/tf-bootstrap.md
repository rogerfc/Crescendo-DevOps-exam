# Terraform Bootstrap — Manual Steps (Step 0)

One-time setup before running any `terraform` command. All resources are created outside Terraform intentionally — they must exist before the backend can be initialised.

**Prerequisites:** AWS CLI configured with credentials that have admin (or equivalent) permissions.

---

## 0a — S3 bucket for Terraform state

```bash
aws s3api create-bucket \
  --bucket rfirpo-crescendo-tfstate \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3api put-bucket-versioning \
  --bucket rfirpo-crescendo-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket rfirpo-crescendo-tfstate \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws s3api put-public-access-block \
  --bucket rfirpo-crescendo-tfstate \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

> **Note:** No DynamoDB table is needed. Terraform 1.10+ supports native S3 locking via `use_lockfile = true`, which stores a `.tflock` file alongside the state in the same bucket.

---

## 0b — OIDC Identity Provider

The provider is account-wide. Check whether it already exists before creating:

```bash
aws iam list-open-id-connect-providers
```

If `token.actions.githubusercontent.com` is **not** listed, create it:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

---

## 0c — IAM Role for GitHub Actions

The trust policy (`trust-policy.json`) and permissions policy (`tf-policy.json`) are in this directory.

### Create the role

```bash
aws iam create-role \
  --role-name rfirpo-crescendo-github-actions \
  --assume-role-policy-document file://tf-bootstrap/trust-policy.json \
  --description "Assumed by GitHub Actions via OIDC for Terraform"
```

### Apply the permissions policy

```bash
aws iam put-role-policy \
  --role-name rfirpo-crescendo-github-actions \
  --policy-name crescendo-terraform-policy \
  --policy-document file://tf-bootstrap/tf-policy.json
```

### Note the Role ARN

```bash
aws iam get-role \
  --role-name rfirpo-crescendo-github-actions \
  --query "Role.Arn" \
  --output text
```

---

## 0d — GitHub secret

In the GitHub repository → **Settings → Secrets and variables → Actions → New repository secret**:

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | the ARN from step 0c |

---

## Verify

```bash
# S3 bucket exists and versioning is enabled
aws s3api get-bucket-versioning --bucket rfirpo-crescendo-tfstate

# IAM role exists
aws iam get-role --role-name rfirpo-crescendo-github-actions --query "Role.Arn"
```

Once both return expected output, run `terraform init` from the `terraform/` directory.
