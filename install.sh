cat > install-fix.sh <<'EOF'
set -eu
REPO=as8869441/vohive-release
CHANNEL=stable
VERSION=""
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

SYSTEMD_SERVICE_PATH=/etc/systemd/system/vohive.service
OPENWRT_INIT_PATH=/etc/init.d/vohive
OPENWRT_RELEASE_FILE=/etc/openwrt_release
PROCD_PATH=/sbin/procd
SYSTEMD_RUN_DIR=/run/systemd/system

DOWNLOAD_CMD=""
TMP_DIR=""
ACTIVE_PLATFORM="none"

# 强制硬编码，跳过uname检测
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
    if ! command -v "$1" >/dev/null 2>&1; then
        err "缺失必要命令: $1"
    fi
}

need_download_cmd() {
    if command -v curl >/dev/null; then
        DOWNLOAD_CMD="curl -fsSL"
        return
    fi
    if command -v wget >/dev/null; then
        DOWNLOAD_CMD="wget -qO-"
        return
    fi
    err "未检测到 curl / wget，请先安装下载工具"
}

download() {
    local url="$1"
    $DOWNLOAD_CMD "$url"
}

get_latest_version() {
    download "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d '"' -f4
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
    # OpenWrt procd 初始化脚本
    if [ -f "$PROCD_PATH" ] && [ -f "$OPENWRT_RELEASE_FILE" ]; then
        cat > "$OPENWRT_INIT_PATH" <<SCRIPT
#!/bin/sh /etc/rc.common
START=99
STOP=10

start() {
    $BIN_PATH start
}
stop() {
    $BIN_PATH stop
}
restart() {
    $BIN_PATH restart
}
SCRIPT
        chmod +x "$OPENWRT_INIT_PATH"
        info "已生成 OpenWrt 自启脚本 /etc/init.d/vohive"
    elif [ "$NO_SYSTEMD" = 0 ] && [ -d "$SYSTEMD_RUN_DIR" ]; then
        cat > "$SYSTEMD_SERVICE_PATH" <<UNIT
[Unit]
Description=VoHive Proxy Service
After=network.target

[Service]
ExecStart=$BIN_PATH start
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
        systemctl daemon-reload
        info "已生成 systemd 服务单元"
    fi
}

main() {
    parse_args "$@"
    need_cmd uname
    need_cmd mktemp
    need_download_cmd

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    if [ -z "$VERSION" ]; then
        VERSION=$(get_latest_version)
    fi
    info "待安装版本: $VERSION 架构: $arch"

    case "$arch" in
        aarch64) BIN_FILE="vohive-linux-arm64" ;;
        x86_64)  BIN_FILE="vohive-linux-amd64" ;;
        *) err "不支持架构: $arch" ;;
    esac

    BIN_URL="https://github.com/${REPO}/releases/download/${VERSION}/${BIN_FILE}"
    info "开始下载程序: $BIN_URL"

    if [ "$DRY_RUN" -eq 0 ]; then
        download "$BIN_URL" > "${TMP_DIR}/vohive"
    fi

    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"

    if [ -f "$BIN_PATH" ]; then
        cp "$BIN_PATH" "$BACKUP_PATH"
        info "已备份旧版本程序"
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        mv "${TMP_DIR}/vohive" "$BIN_PATH"
        chmod +x "$BIN_PATH"
    fi

    install_service
    info "VoHive 安装完成，输入 vohive 即可使用"
}

main "$@"
EOF
