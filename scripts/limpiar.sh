#!/usr/bin/env bash
# Plan B cuando se pierde el tfstate (por ejemplo si las credenciales caducan a mitad
# de un apply): borra por nombre todo lo que crea Terraform y quita el candado del state.
# Para el caso normal usar el workflow Destroy.
#
#   bash scripts/limpiar.sh
set -uo pipefail
export AWS_PAGER=""
P="todo-api"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" || exit 1
BUCKET="todo-tfstate-${ACCOUNT_ID}"
KEY="to-do-list-api/terraform.tfstate"

read -r -p "se van a borrar todos los recursos ${P} de la cuenta ${ACCOUNT_ID}. escribe 'limpiar' para seguir: " ok
[ "$ok" = "limpiar" ] || exit 1

echo "-> EC2"
IDS="$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${P}" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)"
if [ -n "$IDS" ]; then
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids $IDS >/dev/null
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $IDS
  echo "   terminadas: $IDS"
fi

echo "-> RDS ${P}-db"
ESTADO="$(aws rds describe-db-instances --db-instance-identifier "${P}-db" \
  --query "DBInstances[0].DBInstanceStatus" --output text 2>/dev/null || true)"
if [ -n "$ESTADO" ]; then
  if [ "$ESTADO" != "available" ] && [ "$ESTADO" != "stopped" ] && [ "$ESTADO" != "deleting" ]; then
    echo "   esta en '$ESTADO', esperando a que este disponible para poder borrarla..."
    aws rds wait db-instance-available --db-instance-identifier "${P}-db"
  fi
  aws rds delete-db-instance --db-instance-identifier "${P}-db" \
    --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1
  echo "   borrando (tarda unos minutos)..."
  aws rds wait db-instance-deleted --db-instance-identifier "${P}-db"
fi
aws rds delete-db-subnet-group --db-subnet-group-name "${P}-db" 2>/dev/null && echo "   subnet group borrado"

echo "-> security groups"
for sg in "${P}-rds" "${P}-app"; do
  ID="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)"
  if [ -n "$ID" ] && [ "$ID" != "None" ]; then
    aws ec2 delete-security-group --group-id "$ID" && echo "   $sg borrado"
  fi
done

echo "-> key pair"
aws ec2 delete-key-pair --key-name "${P}-key" >/dev/null 2>&1 && echo "   ${P}-key borrado"

echo "-> secretos"
for s in $(aws secretsmanager list-secrets --filters Key=name,Values="${P}/rds-" --query "SecretList[].ARN" --output text); do
  aws secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery >/dev/null && echo "   $s borrado"
done

echo "-> alarmas y dashboard"
ALARMAS="$(aws cloudwatch describe-alarms --alarm-name-prefix "${P}-" --query "MetricAlarms[].AlarmName" --output text)"
# shellcheck disable=SC2086
[ -n "$ALARMAS" ] && aws cloudwatch delete-alarms --alarm-names $ALARMAS && echo "   $ALARMAS"
aws cloudwatch delete-dashboards --dashboard-names "$P" >/dev/null 2>&1 && echo "   dashboard borrado"

echo "-> SNS"
aws sns delete-topic --topic-arn "arn:aws:sns:us-east-1:${ACCOUNT_ID}:${P}-alertas" 2>/dev/null && echo "   topico borrado"

echo "-> state y candado en s3://${BUCKET}"
aws s3 rm "s3://${BUCKET}/${KEY}.tflock" 2>/dev/null
aws s3 rm "s3://${BUCKET}/${KEY}" 2>/dev/null
echo "   listo (el bucket tiene versionado, las versiones anteriores se conservan)"

echo
echo "cuenta limpia, ya se puede correr Provision otra vez"
