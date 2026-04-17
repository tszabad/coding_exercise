# coding_exercise

A serverless data pipeline on AWS that automatically preprocesses car dataset CSV files as they land in S3, deploying all infrastructure via Terraform with a GitHub Actions CI/CD workflow.

## Architecture

```
S3 Landing Bucket (pre-existing)
        │  (ObjectCreated *.csv)
        ▼
AWS Lambda (car-data-preprocessing, Python 3.12)
        │
        ▼
S3 Curated Zone Bucket (Terraform-managed)
```

1. A CSV file is uploaded to the **landing bucket** (`tamas-s3-landing-bucket-*`).
2. An S3 event notification triggers the **Lambda function**.
3. The Lambda reads the file, applies preprocessing, and writes `<filename>_preprocessed.csv` to the **curated zone bucket**.

## Repository structure

```
coding_exercise/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD: Terraform plan on PRs, apply on merge to main
├── resources/
│   └── lambda/
│       └── preprocessing_input_data/
│           └── car_data_preprocessing.py   # Lambda handler
└── terraform/
    ├── provider.tf             # AWS provider + S3 remote state backend
    ├── main.tf                 # All AWS resources
    ├── variables.tf            # Input variables with defaults
    └── output.tf               # Exported resource identifiers
```

## Lambda preprocessing logic

File: [resources/lambda/preprocessing_input_data/car_data_preprocessing.py](resources/lambda/preprocessing_input_data/car_data_preprocessing.py)

- **Drops non-predictive columns**: `car_ID`, `CarName`, `ownername`, `owneremail`, `dealershipaddress`, `saledate`, `iban`
- **Drops rows** with missing values in required columns: `Price`, `fueltype`, `enginesize`
- Rejects non-CSV files and empty dataframes with a `400` response
- Runtime: Python 3.12 with the public AWS SDK for Pandas Lambda layer (`AWSSDKPandas-Python312:22`)

## Terraform resources

File: [terraform/main.tf](terraform/main.tf)

| Resource | Description |
|---|---|
| `aws_s3_bucket.curated_zone_bucket` | Output bucket for preprocessed files, private, versioned, AES-256 encrypted |
| `aws_lambda_function.preprocessing` | Lambda (`car-data-preprocessing`), 256 MB, 60 s timeout |
| `aws_iam_role_policy.lambda_s3` | Least-privilege policy: `GetObject` on landing, `PutObject` on curated |
| `aws_lambda_permission.allow_s3` | Grants the landing bucket permission to invoke the Lambda |
| `aws_s3_bucket_notification.landing_trigger` | S3 event notification filtered to `.csv` uploads |

Remote state is stored in `snapsoft-homework-tf-state-tsz` (eu-north-1).

## CI/CD

File: [.github/workflows/deploy.yml](.github/workflows/deploy.yml)

| Trigger | Job |
|---|---|
| Pull request to `main` | `terraform plan` (preview only) |
| Push / merge to `main` | `terraform apply -auto-approve` |
| Manual (`workflow_dispatch`) | `terraform apply -auto-approve` |

AWS credentials are provided via `AWS_ACCESS_KEY` and `AWS_SECRET` repository secrets.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `eu-north-1` | AWS region |
| `bucket_curated_zone` | `snapsoft-homework-curated-zone-tsz` | Output bucket name |
| `pandas_layer_arn` | `arn:aws:lambda:eu-north-1:336392948345:layer:AWSSDKPandas-Python312:22` | Pandas Lambda layer ARN |
