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
arch=""

err() {
    printf '[vohive-install] 错误: %s\n' "$1" >&2
    exit 1
}
info() {
    printf '[vohive-install] %s\n' "$1"
}
need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "缺失依赖命令: $1"
    fi
}
need_download_cmd() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_CMD="curl -fsSL"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget -qO-"
        return
    fi
    err "请先安装 curl 或 wget"
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

detect_arch() {
    local uname_arch=$(uname -m)
    case "$uname_arch" in
        aarch64|arm64)
            arch="arm64"
            ;;
        x86_64|amd64)
            arch="amd64"
            ;;
        *)
            err "不支持的CPU架构: $uname_arch"
            ;;
    esac
}

gen_default_config() {
    local cfg="$CONFIG_DIR/config.yaml"
    if [ ! -f "$cfg" ]; then
        info "生成默认配置文件 $cfg"
        cat > "$cfg" <<YAML
listen: 0.0.0.0:7575
data_path: /opt/vohive/data
log_path: /opt/vohive/logs
log_level: info
auth:
  enable: true
  username: admin
  password: admin
YAML
    else
        info "检测到已有配置文件，跳过生成默认配置"
    fi
}

install_service() {
    if [ -f "$PROCD_PATH" ]; then
        cat > "$OPENWRT_INIT_PATH" <<SVC
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

BIN=/opt/vohive/bin/vohive
CONF=/opt/vohive/config/config.yaml

start_service() {
    procd_open_instance
    procd_set_param command "\$BIN" -c "\$CONF"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
SVC
        chmod +x "$OPENWRT_INIT_PATH"
        # 改用标准两条命令确保开机自启生效
        /etc/init.d/vohive disable
        /etc/init.d/vohive enable
        info "已生成procd脚本并强制开启开机自启: $OPENWRT_INIT_PATH"
    fi
}

main() {
    parse_args "$@"
    detect_arch
    need_cmd mktemp
    need_download_cmd

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    info "安装版本: $VERSION 架构: $arch"
    BIN_FILE="vohive-linux-$arch"
    BIN_URL="https://github.com/$REPO/releases/download/$VERSION/$BIN_FILE"
    info "下载地址: $BIN_URL"

    if [ "$DRY_RUN" -eq 0 ]; then
        info "正在下载二进制文件..."
        download "$BIN_URL" > "${TMP_DIR}/vohive"
    fi

    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    gen_default_config

    if [ -f "$BIN_PATH" ]; then
        cp "$BIN_PATH" "$BACKUP_PATH"
        info "旧程序已备份至 $BACKUP_PATH"
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        mv "${TMP_DIR}/vohive" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        ln -sf "$BIN_PATH" /usr/bin/vohive
        info "二进制文件部署完成，全局软链接 /usr/bin/vohive"
    fi

    install_service

    info "========================================"
    info "安装完成！管理服务使用以下命令："
    info "  /etc/init.d/vohive start    启动服务"
    info "  /etc/init.d/vohive stop     停止服务"
    info "  /etc/init.d/vohive restart  重启服务"
    info "  /etc/init.d/vohive status   查看运行状态"
    info "  logread -f | grep vohive    实时查看日志"
    info "面板地址：http://路由器IP:7575 账号admin 密码admin"
    info "========================================"
}

main "$@"
EOF
chmod +x install-vohive-fix.sh
sh install-vohive-fix.sh
