#!/usr/bin/env bash
# Daftarkan GitHub Actions self-hosted runner sebagai systemd USER service.
# Pakai: bash scripts/install-runner.sh <owner/repo> <REGISTRATION_TOKEN> [label]
# Token: repo Settings -> Actions -> Runners -> New self-hosted runner.
set -euo pipefail

REPO="${1:?owner/repo}"
TOKEN="${2:?registration token}"
LABEL="${3:-app}"
RUNNER_DIR="$HOME/actions-runner"
VERSION="${RUNNER_VERSION:-2.321.0}"

mkdir -p "$RUNNER_DIR" && cd "$RUNNER_DIR"

if [ ! -x ./config.sh ]; then
  curl -fsSL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-x64-${VERSION}.tar.gz"
  tar xzf runner.tar.gz && rm runner.tar.gz
fi

# --replace: aman kalau runner lama sudah mati/hilang dari GitHub.
./config.sh --unattended --replace \
  --url "https://github.com/${REPO}" \
  --token "$TOKEN" \
  --labels "$LABEL" \
  --name "$(hostname)-$(echo "$LABEL" | tr -c 'a-zA-Z0-9\n' '-')" \
  --work _work

UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/gh-runner.service" <<EOF
[Unit]
Description=GitHub Actions Runner (${REPO})
After=network-online.target

[Service]
Type=simple
WorkingDirectory=${RUNNER_DIR}
ExecStart=${RUNNER_DIR}/run.sh
Restart=always
RestartSec=10
KillMode=process
# Runner tidak mewarisi env shell: KUBECONFIG wajib di-set di sini.
Environment=HOME=${HOME}
Environment=KUBECONFIG=${HOME}/.kube/config
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now gh-runner.service

# Tanpa linger, service mati saat sesi SSH terputus.
sudo loginctl enable-linger "$USER" || echo "WARN: jalankan 'sudo loginctl enable-linger $USER' manual"

sleep 3
systemctl --user status gh-runner.service --no-pager | head -12
