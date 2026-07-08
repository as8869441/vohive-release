cat > install-vohive-fix.sh <<'EOF'
set -eu
REPO=as8869441/vohive-release
VERSION="v1.5.5"
NO_SYSTEMD=0
DRY_RUN=0
FORCE=0

ROOT_DIR=/opt/vohive
INSTALL_DIR=/opt/vohive/bin
CONFIG_DIR=/opt/vohive/config
DATA_DIR=/opt/vohive/data
LOG_DIR=/opt/vohive/logs
BIN_PATH=/opt/vohive/bin/vohive
BACKUP_PATH=/opt/vohive/bin/vohive.bak

OPENWRT_INIT_PATH=/etc/init.d/vohive
PROCD_PATH=/sbin/procd

DOWNLOAD_CMD=""
TMP_DIR=""

# 硬编码绕过系统检测
os="linux"
arch="aarch64"

err() {
    printf '[vohive-install] 错误: %s\n' "$1"
    exit 1
}
info() {
    printf '[vohive-install] %s\n' "$1"
}
need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then err "缺失命令: $1"; fi
}
need_download_cmd() {
    if command -v curl >/dev/null; then DOWNLOAD_CMD="curl -fsSL"; return; fi
    if command -v wget >/dev/null; then DOWNLOAD_CMD="wget -qO-"; return; fi
    err "请安装 curl 或 wget"
}
download() {
    local url="$1"
    $DOWNLOAD_CMD "$url"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-systemd) NO_SYSTEMD=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --force) FORCE=1 ;;
            -v|--version) VERSION="$2"; shift ;;
        esac
        shift
    done
}

install_service() {
    if [ -f "$PROCD_PATH" ]; then
        cat > "$OPENWRT_INIT_PATH" <<SVC
#!/bin/sh /etc/rc.common
START=99
STOP=10
start() { $BIN_PATH start; }
stop() { $BIN_PATH stop; }
restart() { $BIN_PATH restart; }
SVC
        chmod +x "$OPENWRT_INIT_PATH"
        info "已创建OpenWrt自启脚本 /etc/init.d/vohive"
    fi
}

main() {
    parse_args "$@"
    need_cmd mktemp
    need_download_cmd

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

      info "安装版本: $VERSION 架构: $arch"
    BIN_FILE="vohive-linux-arm64"
    # ghproxy 加速地址
    RAW_URL="https://github.com/$REPO/releases/download/$VERSION/$BIN_FILE"
    info "镜像下载地址: $BIN_URL"

    if [ "$DRY_RUN" -eq 0 ]; then
        download "$BIN_URL" > "${TMP_DIR}/vohive"
    fi

    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    [ -f "$BIN_PATH" ] && cp "$BIN_PATH" "$BACKUP_PATH" && info "备份旧程序"
    if [ "$DRY_RUN" -eq 0 ]; then
        mv "${TMP_DIR}/vohive" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        ln -sf "$BIN_PATH" /usr/bin/vohive
    fi
    install_service
    info "安装完成，执行 vohive start 启动"
}

main "$@"
EOF
