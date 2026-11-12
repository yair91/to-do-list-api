#!/usr/bin/env bash
# Crea (una sola vez por cuenta) el bucket de S3 donde vive el tfstate.
# Correr en la consola de AWS Academy (CloudShell):
#
#   bash scripts/crear-backend.sh
set -euo pipefail
export AWS_PAGER=""
REGION="${AWS_REGION:-us-east-1}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="todo-tfstate-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "el bucket $BUCKET ya existe"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  echo "bucket $BUCKET creado"
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "versionado, cifrado y acceso publico bloqueado"
echo "el tfstate va a quedar en s3://${BUCKET}/to-do-list-api/terraform.tfstate"
