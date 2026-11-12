#!/usr/bin/env bash
# Pruebas rapidas contra la API desplegada.
#
#   bash scripts/probar-api.sh            -> health, version, crea una tarea y lista
#   bash scripts/probar-api.sh errores 10 -> 10 peticiones (con RDS detenida generan DbErrors)
#   bash scripts/probar-api.sh pico 60    -> crea 60 tareas (dispara la alarma de pico)
set -euo pipefail
export AWS_PAGER=""

IP="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=todo-api" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)"
[ "$IP" != "None" ] || { echo "no hay instancia todo-api corriendo"; exit 1; }
API="http://$IP:8000"
echo "API: $API"

case "${1:-basico}" in
  basico)
    curl -s "$API/health"; echo
    curl -s "$API/version"; echo
    curl -s -X POST "$API/tasks" -H "Content-Type: application/json" \
      -d '{"title": "estudiar para el examen de desarrollo en la nube", "done": false}'; echo
    curl -s "$API/tasks"; echo
    ;;
  errores)
    for i in $(seq 1 "${2:-10}"); do
      printf "GET /tasks -> %s\n" "$(curl -s -o /dev/null -w '%{http_code}' "$API/tasks")"
    done
    ;;
  pico)
    for i in $(seq 1 "${2:-60}"); do
      curl -s -o /dev/null -X POST "$API/tasks" -H "Content-Type: application/json" \
        -d "{\"title\": \"tarea de carga $i\"}"
    done
    echo "${2:-60} tareas creadas"
    ;;
  *)
    echo "uso: probar-api.sh [basico|errores N|pico N]"
    exit 1
    ;;
esac
