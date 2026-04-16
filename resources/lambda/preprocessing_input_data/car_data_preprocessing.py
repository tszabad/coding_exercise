import json
import os
import pandas as pd
import boto3
import logging

handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter(
    fmt="%(asctime)s %(levelname)s %(message)s",
    datefmt="%d-%m-%Y %H:%M:%S"
))

logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.addHandler(handler)

s3_client = boto3.client('s3')

NON_PREDICTIVE_COLS = ['car_ID', 'CarName', 'ownername', 'owneremail', 'dealershipaddress', 'saledate', 'iban']
REQUIRED_COLS = ['Price', 'fueltype', 'enginesize']

# Function to read data from S3
def get_source_data(bucket_name, s3_file_name):
    obj = s3_client.get_object(Bucket=bucket_name, Key=s3_file_name)
    return pd.read_csv(obj['Body'])

# Function to preprocess the data
def preprocess_data(df):
    df = df.drop(columns=NON_PREDICTIVE_COLS)
    df = df.dropna(subset=REQUIRED_COLS)
    return df

# Function to save preprocessed data back to S3
def save_preprocessed_data(df, bucket_name, s3_file_name):
    csv_buffer = df.to_csv(index=False)
    s3_client.put_object(Bucket=bucket_name, Key=s3_file_name, Body=csv_buffer)

# Lambda handler function
def lambda_handler(event, context):
    try:
        bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        target_bucket_name = os.environ["TARGET_BUCKET"]
        s3_file_name = event["Records"][0]["s3"]["object"]["key"]
        # Validate file type
        if not s3_file_name.endswith('.csv'):
            logger.error("File %s is not a CSV file.", s3_file_name)
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid file type. Only CSV files are allowed.')
            }

        logger.info(f"Reading s3://{bucket_name}/{s3_file_name}")
        df = get_source_data(bucket_name, s3_file_name)
        # Check if the dataframe is empty
        if df.empty:
            logger.warning("Loaded dataframe is empty.")
            return {
                'statusCode': 400,
                'body': json.dumps('The dataframe is empty.')
            }

        logger.info(f"Loaded dataframe shape: {df.shape}")
        # Process the data
        df = preprocess_data(df)
        save_preprocessed_data(df, target_bucket_name, s3_file_name)
        logger.info(f"Preprocessed data saved to {target_bucket_name}/{s3_file_name}")

        return {
            'statusCode': 200,
            'body': json.dumps(f'File {s3_file_name} preprocessed and saved to {target_bucket_name}.')
        }

    except Exception as e:
        logger.exception("Failed to process S3 event")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Internal server error: {str(e)}')
        }