# coding_exercise

A serverless data pipeline on AWS that automatically preprocesses car dataset CSV files as they land in S3, deploying all infrastructure via Terraform with a GitHub Actions CI/CD workflow. A Jupyter notebook trains and evaluates machine learning models on the preprocessed data to predict car selling prices.

## Architecture

```
S3 Landing Bucket (pre-existing)
        │  (ObjectCreated *.csv)
        ▼
AWS Lambda (car-data-preprocessing, Python 3.12)
        │
        ▼
S3 Curated Zone Bucket (Terraform-managed)
        │
        ▼
Jupyter Notebook (price_prediction/car_selling_price_prediction.ipynb)
```

1. A CSV file is uploaded to the **landing bucket** (`tamas-s3-landing-bucket-*`).
2. An S3 event notification triggers the **Lambda function**.
3. The Lambda reads the file, applies preprocessing, and writes `<filename>_preprocessed.csv` to the **curated zone bucket**.
4. The notebook reads from the curated zone, trains several models, and selects the one that best satisfies the business requirement of slight price underestimation.

## Repository structure

```
coding_exercise/
├── .github/
│   └── workflows/
│       └── deploy.yml                          # CI/CD: Terraform plan on PRs, apply on merge to main
├── price_prediction/
│   └── car_selling_price_prediction.ipynb      # ML training and evaluation notebook
├── resources/
│   └── lambda/
│       └── preprocessing_input_data/
│           └── car_data_preprocessing.py       # Lambda handler
└── terraform/
    ├── provider.tf                             # AWS provider + S3 remote state backend
    ├── main.tf                                 # All AWS resources
    ├── variables.tf                            # Input variables with defaults
    └── output.tf                               # Exported resource identifiers
```

## Prerequisites

Before deploying, ensure you have the following installed and configured:

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.14.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials that have permissions to manage S3, Lambda, and IAM
- The S3 remote state bucket (`snapsoft-homework-tf-state-tsz`) must already exist in `eu-north-1`
- The IAM execution role (`preprocessing_input_data-role-9mmvm4mx`) must already exist (it is referenced, not created, by Terraform)

## Terraform deployment

All commands below must be run from the `terraform/` directory:

```bash
cd terraform
```

### 1. Initialise

Downloads the required providers (`hashicorp/aws`, `hashicorp/archive`) and configures the S3 remote state backend.

```bash
terraform init
```

### 2. Preview changes

Produces a plan showing exactly what will be created, updated, or destroyed without making any changes.

```bash
terraform plan
```

To override a variable at plan time (e.g. use a different curated zone bucket name):

```bash
terraform plan -var="bucket_curated_zone=my-custom-bucket-name"
```

### 3. Apply

Creates or updates all AWS resources. You will be prompted for confirmation unless `-auto-approve` is passed.

```bash
terraform apply
```

Non-interactive apply (used in CI/CD):

```bash
terraform apply -auto-approve
```

After a successful apply, Terraform prints the output values:

| Output | Description |
|---|---|
| `landing_bucket_name` | Name of the pre-existing landing S3 bucket |
| `preprocessed_bucket_name` | Name of the newly created curated zone bucket |
| `lambda_function_name` | Name of the deployed Lambda function |
| `lambda_function_arn` | ARN of the deployed Lambda function |


## Configuration

All variables and their defaults are defined in [terraform/variables.tf](terraform/variables.tf). To change a value, edit the `default` field of the relevant variable directly in that file.

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `eu-north-1` | AWS region for all resources |
| `bucket_curated_zone` | `snapsoft-homework-curated-zone-tsz` | Name of the output S3 bucket (curated zone) |
| `pandas_layer_arn` | `arn:aws:lambda:eu-north-1:336392948345:layer:AWSSDKPandas-Python312:22` | ARN of the AWS SDK for Pandas Lambda layer |

## Terraform resources

File: [terraform/main.tf](terraform/main.tf)

| Resource | Type | Description |
|---|---|---|
| `aws_s3_bucket.curated_zone_bucket` | managed | Output bucket for preprocessed files |
| `aws_s3_bucket_versioning` | managed | Versioning enabled on curated bucket |
| `aws_s3_bucket_acl` | managed | Private ACL on curated bucket |
| `aws_s3_bucket_server_side_encryption_configuration` | managed | AES-256 server-side encryption |
| `aws_s3_bucket_public_access_block` | managed | All public access blocked |
| `aws_lambda_function.preprocessing` | managed | Lambda (`car-data-preprocessing`), 256 MB, 60 s timeout |
| `aws_iam_role_policy.lambda_s3` | managed | Least-privilege: `GetObject` on landing, `PutObject` on curated |
| `aws_lambda_permission.allow_s3` | managed | Grants landing bucket permission to invoke Lambda |
| `aws_s3_bucket_notification.landing_trigger` | managed | S3 event notification filtered to `.csv` uploads |
| `data.aws_s3_bucket.landing_bucket` | data (pre-existing) | Reference to the pre-existing landing bucket |
| `data.aws_iam_role.lambda_exec` | data (pre-existing) | Reference to the pre-existing Lambda IAM execution role |

Remote state is stored in `snapsoft-homework-tf-state-tsz` (eu-north-1).

## Lambda preprocessing logic

File: [resources/lambda/preprocessing_input_data/car_data_preprocessing.py](resources/lambda/preprocessing_input_data/car_data_preprocessing.py)

The handler performs the following steps on every `.csv` uploaded to the landing bucket:

1. **Validates** file type, schema (all expected columns present), and that the dataframe is not empty — returns HTTP 400 on any violation.
2. **Drops non-predictive columns**: `car_ID`, `CarName`, `ownername`, `owneremail`, `dealershipaddress`, `saledate`, `iban` — these carry no signal for price prediction.
3. **Drops rows** where any of the required columns (`Price`, `fueltype`, `enginesize`) are missing — these cannot be imputed without introducing significant bias.
4. **Preserves rows** with missing values in non-critical columns (e.g. `carlength`, `cylindernumber`, `enginelocation`) — these are imputed later in the notebook.
5. Writes the result as `<original_filename>_preprocessed.csv` to the curated zone bucket.

Runtime: Python 3.12 with the public AWS SDK for Pandas Lambda layer (`AWSSDKPandas-Python312:22`).

## Machine learning notebook

File: [price_prediction/car_selling_price_prediction.ipynb](price_prediction/car_selling_price_prediction.ipynb) for local usage

or
File: [price_prediction/car_selling_price_prediction.ipynb](price_prediction/car_selling_price_prediction_sagemaker.ipynb) for AWS SageMaker usage


The notebook reads the preprocessed CSV from the file system or from AWS S3 curated zone bucket and trains four sklearn-compatible models:

| Model | Test R² | Test MAE | Avg Error (pred − actual) | Direction |
|---|---|---|---|---|
| Linear Regression | 0.7747 | 2756 | −790 | underestimates |
| Random Forest | 0.9378 | 1501 | +433 | overestimates |
| Gradient Boosting | 0.9295 | 1799 | +960 | overestimates |
| **Quantile GB (α=0.46)** | — | — | **−44** | **slight underestimate** |

**Selected model: Quantile Gradient Boosting (`loss='quantile'`, `alpha=0.46`)**

The quantile loss function targets the 46th percentile of the price distribution, producing predictions that are systematically just below the actual price (~$44 on average). This satisfies the business requirement — the company's listed prices will be slightly below market value, helping to move inventory faster.

Preprocessing within the notebook:
- Imputes missing numeric values with the column median, categorical with the mode
- One-hot encodes `fueltype`, `carbody`, `drivewheel`
- Label-encodes `aspiration`, `doornumber`, `enginelocation`, `color`
- Splits data 80% train / 10% validation / 10% test with `StandardScaler`

## CI/CD

File: [.github/workflows/deploy.yml](.github/workflows/deploy.yml)

| Trigger | Job |
|---|---|
| Pull request to `main` | `terraform plan` (preview only) |
| Push / merge to `main` | `terraform apply -auto-approve` |
| Manual (`workflow_dispatch`) | `terraform apply -auto-approve` |

AWS credentials are injected via `AWS_ACCESS_KEY` and `AWS_SECRET` repository secrets.
