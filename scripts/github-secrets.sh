#!/usr/bin/env bash
# Copia las credenciales de la sesion actual de AWS Academy a los secrets del repo
# para que los workflows puedan usar AWS. Las credenciales del lab caducan,
# hay que correrlo cada vez que se inicia el lab.
#
#   bash scripts/github-secrets.sh tu@correo.com
#
# El correo es opcional despues de la primera vez (se guarda como variable ALERT_EMAIL).
# La primera vez pide iniciar sesion en GitHub (gh auth login).
set -euo pipefail
export AWS_PAGER=""
export PATH="$HOME/bin:$PATH"

CORREO="${1:-}"

if ! command -v gh >/dev/null; then
  echo "-> instalando gh en ~/bin"
  mkdir -p "$HOME/bin"
  VERSION="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r .tag_name | sed 's/^v//')"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /tmp
  mv "/tmp/gh_${VERSION}_linux_amd64/bin/gh" "$HOME/bin/gh"
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "-> inicia sesion en GitHub: copia el codigo y abrelo en tu navegador"
  gh auth login --hostname github.com --git-protocol https --web
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# Las credenciales de CloudShell caducan a los pocos minutos y tiran el terraform apply
# a la mitad, por eso solo se aceptan las de "AWS Details" del lab (duran toda la sesion).
AK="$(aws configure get aws_access_key_id 2>/dev/null || true)"
SK="$(aws configure get aws_secret_access_key 2>/dev/null || true)"
ST="$(aws configure get aws_session_token 2>/dev/null || true)"
if [ -z "$AK" ] || [ -z "$SK" ] || [ -z "$ST" ]; then
  cat <<'MSG'
faltan las credenciales del lab en ~/.aws/credentials:
  1. en la pagina del Learner Lab: AWS Details > AWS CLI > Show
  2. copia el bloque completo ([default], aws_access_key_id, aws_secret_access_key, aws_session_token)
  3. en CloudShell: nano ~/.aws/credentials, pega, guarda (Ctrl+O, Enter, Ctrl+X)
  4. vuelve a correr este script
MSG
  exit 1
fi

ACCOUNT_ID="$(AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST" \
  aws sts get-caller-identity --query Account --output text)"

gh secret set AWS_ACCESS_KEY_ID --repo "$REPO" --body "$AK"
gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO" --body "$SK"
gh secret set AWS_SESSION_TOKEN --repo "$REPO" --body "$ST"
echo "secrets actualizados en $REPO (cuenta $ACCOUNT_ID)"

if [ -n "$CORREO" ]; then
  gh variable set ALERT_EMAIL --repo "$REPO" --body "$CORREO"
  echo "ALERT_EMAIL = $CORREO"
elif [ -z "$(gh variable get ALERT_EMAIL --repo "$REPO" 2>/dev/null || true)" ]; then
  echo "falta el correo para las alarmas: bash scripts/github-secrets.sh tu@correo.com"
  exit 1
fi
