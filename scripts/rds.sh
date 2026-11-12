#!/usr/bin/env bash
# Detiene o arranca la instancia de RDS para probar la alarma de errores.
#
#   bash scripts/rds.sh detener
#   bash scripts/rds.sh arrancar
#   bash scripts/rds.sh estado
set -euo pipefail
export AWS_PAGER=""
DB="${DB_ID:-todo-api-db}"

estado() {
  aws rds describe-db-instances --db-instance-identifier "$DB" \
    --query "DBInstances[0].DBInstanceStatus" --output text
}

case "${1:-estado}" in
  detener)
    aws rds stop-db-instance --db-instance-identifier "$DB" >/dev/null
    echo "deteniendo $DB (tarda unos minutos)..."
    until [ "$(estado)" = "stopped" ]; do sleep 15; echo "  $(estado)"; done
    echo "$DB detenida. Ahora la API responde 503 y la metrica DbErrors sube."
    ;;
  arrancar)
    aws rds start-db-instance --db-instance-identifier "$DB" >/dev/null
    echo "arrancando $DB..."
    aws rds wait db-instance-available --db-instance-identifier "$DB"
    echo "$DB disponible"
    ;;
  estado)
    echo "$DB: $(estado)"
    ;;
  *)
    echo "uso: rds.sh detener|arrancar|estado"
    exit 1
    ;;
esac
