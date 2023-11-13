#!/bin/bash

#for debug mode
set -x

# AWS account ID in a variable
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

# Print the AWS account ID from the variable
echo "AWS Account ID: $aws_account_id"

# Set AWS region and bucket name
aws_region="<GIVE REGION>"
bucket_name="<GIVE YUOR BUCKET NAME>"
lambda_func_name="<LAMBDA FUNCTION NAME>"
role_name="<IAM ROLE>"
email_address="<EMAIL>"

# Create IAM Role 
role_response=$(aws iam create-role --role-name $role_name --assume-role-policy-document file://lambda-sns-Trust-Policy.json

# Extract the role ARN from the JSON response 
role_arn=$(echo "$role_response" | jq -r '.Role.Arn')

# Print the role ARN
echo "Role ARN: $role_arn"

# Attach Permissions to the Role
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess

# Create the S3 bucket
aws s3api create-bucket --bucket "$bucket_name" --region "$aws_region"

# Upload a file to the bucket
aws s3 cp ./test_file.txt s3://"$bucket_name"/test_file.txt

# Create a Zip file to upload Lambda Function
zip -r lambda-s3.zip ./lambda-s3

sleep 5
# Create a Lambda function
aws lambda create-function \
  --region "$aws_region" \
  --function-name $lambda_func_name \
  --runtime "python3.8" \
  --handler "lambda-s3/lambda-s3.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role "arn:aws:iam::$aws_account_id:role/$role_name" \
  --zip-file "fileb://./lambda-s3.zip"

# Add Permissions to S3 Bucket to invoke Lambda
aws lambda add-permission \
  --function-name "$lambda_func_name" \
  --statement-id "s3-lambda-sns" \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$bucket_name"

# Create an S3 event trigger for the Lambda function
LambdaFunctionArn="arn:aws:lambda:us-east-1:$aws_account_id:function:$lambda_func_name"
aws s3api put-bucket-notification-configuration \
  --region "$aws_region" \
  --bucket "$bucket_name" \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$LambdaFunctionArn"'",
        "Events": ["s3:ObjectCreated:*"]
    }]
}'

# Create an SNS topic and save the topic ARN to a variable
topic_arn=$(aws sns create-topic --name s3-lambda-sns --output json | jq -r '.TopicArn')

# Print the TopicArn
echo "SNS Topic ARN: $topic_arn"

# Trigger SNS Topic using Lambda Function


# Add SNS publish permission to the Lambda Function
aws sns subscribe \
  --topic-arn "$topic_arn" \
  --protocol email \
  --notification-endpoint "$email_address"

# Publish SNS
aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "A new object created in s3 bucket" \
  --message "Here something new uploaded"