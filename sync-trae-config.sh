#!/bin/bash

# ==========================================
# Trae 国际版 ↔ 国内版 配置同步脚本 v3.2
# 同步内容：Skills、user_rules、MCP(mcp.json 智能合并)、settings.json(智能合并)、skill-config.json(智能合并)
# ==========================================

set -euo pipefail

TRAE_GLOBAL="$HOME/.trae"
TRAE_CN="$HOME/.trae-cn"
# 真正的 MCP 配置和 IDE 设置在 Application Support 下
TRAE_APP_GLOBAL="$HOME/Library/Application Support/Trae"
TRAE_APP_CN="$HOME/Library/Application Support/Trae CN"
BACKUP_ROOT="$HOME/.trae-sync-backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$BACKUP_ROOT/sync.log"
DRY_RUN=false
AUTO_YES=false
BACKUP_DONE=false
STATS_NEW=0
STATS_UPDATED=0
STATS_SKIPPED=0

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log() {
  local level="$1"
  shift
  local msg="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run|-n)
      DRY_RUN=true
      shift
      ;;
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    --clean)
      echo "🧹 清理 7 天前的备份..."
      find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
      echo "✅ 清理完成"
      exit 0
      ;;
    --help|-h)
      echo "用法: sync-trae-config [选项]"
      echo ""
      echo "选项:"
      echo "  -n, --dry-run    预览模式，只显示不执行"
      echo "  -y, --yes        自动确认，不询问"
      echo "      --clean      清理 7 天前的旧备份"
      echo "  -h, --help       显示帮助"
      echo ""
      echo "同步内容: Skills、user_rules、mcp.json、settings.json、skill-config.json"
      echo "备份位置: $BACKUP_ROOT"
      echo "日志文件: $LOG_FILE"
      exit 0
      ;;
    *)
      echo "未知选项: $1"
      echo "使用 --help 查看帮助"
      exit 1
      ;;
  esac
done

# 确保备份目录存在
mkdir -p "$BACKUP_ROOT"

# 验证目录是否真的是 Trae 配置
validate_trae_dir() {
  local dir="$1"
  local name="$2"
  
  if [ ! -d "$dir" ]; then
    echo -e "${YELLOW}⚠️  $name 目录不存在: $dir${NC}"
    log "WARN" "$name 目录不存在: $dir"
    return 1
  fi
  
  if [ -d "$dir/skills" ] || [ -d "$dir/user_rules" ] || [ -f "$dir/skill-config.json" ]; then
    return 0
  fi
  
  echo -e "${YELLOW}⚠️  $name 目录看起来不像 Trae 配置目录: $dir${NC}"
  echo -e "${YELLOW}   （没有找到 skills、user_rules 或 skill-config.json）${NC}"
  log "WARN" "$name 目录看起来不像 Trae 配置目录"
  
  if [ "$AUTO_YES" = false ]; then
    read -p "   还要继续吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "已取消"
      log "INFO" "用户取消了操作"
      exit 1
    fi
  fi
  return 0
}

# 执行备份
do_backup() {
  if [ "$BACKUP_DONE" = true ]; then
    return
  fi
  
  if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}💾 [预览] 将创建备份: $BACKUP_DIR${NC}"
    BACKUP_DONE=true
    return
  fi
  
  mkdir -p "$BACKUP_DIR"
  
  # 备份 ~/.trae 和 ~/.trae-cn
  if [ -d "$TRAE_GLOBAL" ]; then
    cp -RL "$TRAE_GLOBAL" "$BACKUP_DIR/trae-global" 2>/dev/null || true
    log "INFO" "已备份国际版配置 (~/.trae)"
  fi
  
  if [ -d "$TRAE_CN" ]; then
    cp -RL "$TRAE_CN" "$BACKUP_DIR/trae-cn" 2>/dev/null || true
    log "INFO" "已备份国内版配置 (~/.trae-cn)"
  fi
  
  # 备份 Application Support 下的 mcp.json 和 settings.json
  if [ -d "$TRAE_APP_GLOBAL/User" ]; then
    mkdir -p "$BACKUP_DIR/app-global"
    cp "$TRAE_APP_GLOBAL/User/mcp.json" "$BACKUP_DIR/app-global/mcp.json" 2>/dev/null || true
    cp "$TRAE_APP_GLOBAL/User/settings.json" "$BACKUP_DIR/app-global/settings.json" 2>/dev/null || true
    log "INFO" "已备份国际版 Application Support 配置"
  fi
  
  if [ -d "$TRAE_APP_CN/User" ]; then
    mkdir -p "$BACKUP_DIR/app-cn"
    cp "$TRAE_APP_CN/User/mcp.json" "$BACKUP_DIR/app-cn/mcp.json" 2>/dev/null || true
    cp "$TRAE_APP_CN/User/settings.json" "$BACKUP_DIR/app-cn/settings.json" 2>/dev/null || true
    log "INFO" "已备份国内版 Application Support 配置"
  fi
  
  BACKUP_DONE=true
  echo -e "${GREEN}💾 备份已创建: $BACKUP_DIR${NC}"
  log "INFO" "备份创建完成: $BACKUP_DIR"
}

# 计算文件 MD5
get_file_hash() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo ""
    return
  fi
  md5 -q "$file" 2>/dev/null || echo ""
}

# 获取目录最新文件时间
# 使用 find -L 跟随符号链接，排除 .DS_Store 和 .git
get_latest_mtime() {
  local dir="$1"
  
  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi
  
  local latest=$(find -L "$dir" -type f -not -name '.DS_Store' -not -path '*/.git/*' -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1)
  
  if [ -z "$latest" ]; then
    echo 0
  else
    echo "$latest" | awk '{print $1}'
  fi
}

# 统计文件数
# 使用 find -L 跟随符号链接，排除 .DS_Store 和 .git
count_files() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi
  find -L "$dir" -type f -not -name '.DS_Store' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' '
}

# 同步目录（双向）
# 双向 cp -rnL：各自独有的文件复制到对方，不覆盖已有文件
# 使用 -L 跟随符号链接，确保链接指向的实际文件被正确同步
sync_dir() {
  local dir_name="$1"
  local global_dir="$TRAE_GLOBAL/$dir_name"
  local cn_dir="$TRAE_CN/$dir_name"
  
  echo ""
  echo -e "${BLUE}📁 同步 $dir_name...${NC}"
  
  local global_count=$(count_files "$global_dir")
  local cn_count=$(count_files "$cn_dir")
  
  echo -e "   国际版: ${CYAN}$global_count 个文件${NC} | 国内版: ${CYAN}$cn_count 个文件${NC}"
  
  if [ ! -d "$global_dir" ] && [ ! -d "$cn_dir" ]; then
    echo -e "   ${YELLOW}ℹ️  两边都没有，跳过${NC}"
    log "INFO" "$dir_name: 两边都没有，跳过"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    return
  fi
  
  if [ -d "$global_dir" ] && [ ! -d "$cn_dir" ]; then
    echo -e "   ⬇️  国际版 -> 国内版（国内版没有）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $dir_name 到国内版（新增 $global_count 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + global_count))
    else
      do_backup
      mkdir -p "$TRAE_CN"
      cp -rL "$global_dir" "$cn_dir"
      echo -e "   ${GREEN}✅ 已同步（新增 $global_count 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + global_count))
      log "INFO" "$dir_name: 从国际版同步到国内版，新增 $global_count 个文件"
    fi
    return
  fi
  
  if [ ! -d "$global_dir" ] && [ -d "$cn_dir" ]; then
    echo -e "   ⬆️  国内版 -> 国际版（国际版没有）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $dir_name 到国际版（新增 $cn_count 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + cn_count))
    else
      do_backup
      mkdir -p "$TRAE_GLOBAL"
      cp -rL "$cn_dir" "$global_dir"
      echo -e "   ${GREEN}✅ 已同步（新增 $cn_count 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + cn_count))
      log "INFO" "$dir_name: 从国内版同步到国际版，新增 $cn_count 个文件"
    fi
    return
  fi
  
  # 两边都存在：双向同步
  echo -e "   🔄 双向同步（不覆盖已有文件）"
  
  local total_added=0
  
  # global -> cn
  if [ "$DRY_RUN" = true ]; then
    local global_mtime=$(get_latest_mtime "$global_dir")
    local cn_mtime=$(get_latest_mtime "$cn_dir")
    if [ "$global_mtime" -gt "$cn_mtime" ]; then
      echo -e "   ${BLUE}[预览] 国际版 -> 国内版（国际版更新）${NC}"
    else
      echo -e "   ${BLUE}[预览] 国际版 -> 国内版${NC}"
    fi
  else
    do_backup
    local before_cn=$(count_files "$cn_dir")
    cp -rnL "$global_dir"/* "$cn_dir/" 2>/dev/null || true
    local after_cn=$(count_files "$cn_dir")
    local added_cn=$((after_cn - before_cn))
    if [ "$added_cn" -gt 0 ]; then
      echo -e "   ${GREEN}✅ 国际版 -> 国内版（新增 $added_cn 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + added_cn))
      total_added=$((total_added + added_cn))
    else
      echo -e "   ${YELLOW}ℹ️  国际版 -> 国内版（没有新文件）${NC}"
    fi
    log "INFO" "$dir_name: 从国际版同步到国内版，新增 $added_cn 个文件"
  fi
  
  # cn -> global
  if [ "$DRY_RUN" = true ]; then
    local global_mtime=$(get_latest_mtime "$global_dir")
    local cn_mtime=$(get_latest_mtime "$cn_dir")
    if [ "$cn_mtime" -gt "$global_mtime" ]; then
      echo -e "   ${BLUE}[预览] 国内版 -> 国际版（国内版更新）${NC}"
    else
      echo -e "   ${BLUE}[预览] 国内版 -> 国际版${NC}"
    fi
  else
    local before_global=$(count_files "$global_dir")
    cp -rnL "$cn_dir"/* "$global_dir/" 2>/dev/null || true
    local after_global=$(count_files "$global_dir")
    local added_global=$((after_global - before_global))
    if [ "$added_global" -gt 0 ]; then
      echo -e "   ${GREEN}✅ 国内版 -> 国际版（新增 $added_global 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + added_global))
      total_added=$((total_added + added_global))
    else
      echo -e "   ${YELLOW}ℹ️  国内版 -> 国际版（没有新文件）${NC}"
    fi
    log "INFO" "$dir_name: 从国内版同步到国际版，新增 $added_global 个文件"
  fi
  
  if [ "$total_added" -eq 0 ] && [ "$DRY_RUN" = false ]; then
    echo -e "   ${YELLOW}ℹ️  两边文件相同，无需同步${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
  fi
}

# 同步文件
sync_file() {
  local file_name="$1"
  local global_file="$TRAE_GLOBAL/$file_name"
  local cn_file="$TRAE_CN/$file_name"
  
  echo ""
  echo -e "${BLUE}📄 同步 $file_name...${NC}"
  
  if [ ! -f "$global_file" ] && [ ! -f "$cn_file" ]; then
    echo -e "   ${YELLOW}ℹ️  两边都没有，跳过${NC}"
    log "INFO" "$file_name: 两边都没有，跳过"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    return
  fi
  
  if [ -f "$global_file" ] && [ ! -f "$cn_file" ]; then
    echo -e "   ⬇️  国际版 -> 国内版"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国内版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      mkdir -p "$TRAE_CN"
      cp "$global_file" "$cn_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 从国际版同步到国内版"
    fi
    return
  fi
  
  if [ ! -f "$global_file" ] && [ -f "$cn_file" ]; then
    echo -e "   ⬆️  国内版 -> 国际版"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国际版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      mkdir -p "$TRAE_GLOBAL"
      cp "$cn_file" "$global_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 从国内版同步到国际版"
    fi
    return
  fi
  
  global_hash=$(get_file_hash "$global_file")
  cn_hash=$(get_file_hash "$cn_file")
  
  if [ "$global_hash" = "$cn_hash" ] && [ -n "$global_hash" ]; then
    echo -e "   ${GREEN}✅ 内容完全相同，跳过${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    log "INFO" "$file_name: 内容相同，跳过"
    return
  fi
  
  global_mtime=$(stat -f "%m" "$global_file" 2>/dev/null || echo 0)
  cn_mtime=$(stat -f "%m" "$cn_file" 2>/dev/null || echo 0)
  
  if [ "$global_mtime" -gt "$cn_mtime" ]; then
    echo -e "   ⬇️  国际版 -> 国内版（国际版更新）"
    echo -e "   ${YELLOW}⚠️  内容不同，将覆盖国内版的 $file_name${NC}"
    
    if [ "$DRY_RUN" = true ]; then
      STATS_UPDATED=$((STATS_UPDATED + 1))
    else
      if [ "$AUTO_YES" = false ]; then
        read -p "   确认覆盖吗？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo -e "   ${YELLOW}⏭️  已跳过${NC}"
          log "INFO" "$file_name: 用户跳过覆盖"
          STATS_SKIPPED=$((STATS_SKIPPED + 1))
          return
        fi
      fi
      
      do_backup
      cp "$global_file" "$cn_file"
      echo -e "   ${GREEN}✅ 已覆盖${NC}"
      STATS_UPDATED=$((STATS_UPDATED + 1))
      log "INFO" "$file_name: 从国际版覆盖到国内版"
    fi
  elif [ "$cn_mtime" -gt "$global_mtime" ]; then
    echo -e "   ⬆️  国内版 -> 国际版（国内版更新）"
    echo -e "   ${YELLOW}⚠️  内容不同，将覆盖国际版的 $file_name${NC}"
    
    if [ "$DRY_RUN" = true ]; then
      STATS_UPDATED=$((STATS_UPDATED + 1))
    else
      if [ "$AUTO_YES" = false ]; then
        read -p "   确认覆盖吗？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo -e "   ${YELLOW}⏭️  已跳过${NC}"
          log "INFO" "$file_name: 用户跳过覆盖"
          STATS_SKIPPED=$((STATS_SKIPPED + 1))
          return
        fi
      fi
      
      do_backup
      cp "$cn_file" "$global_file"
      echo -e "   ${GREEN}✅ 已覆盖${NC}"
      STATS_UPDATED=$((STATS_UPDATED + 1))
      log "INFO" "$file_name: 从国内版覆盖到国际版"
    fi
  else
    echo -e "   ${YELLOW}ℹ️  时间相同但内容不同，跳过（请手动合并）${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    log "WARN" "$file_name: 时间相同但内容不同，需要手动合并"
  fi
}

confirm() {
  if [ "$AUTO_YES" = true ] || [ "$DRY_RUN" = true ]; then
    return 0
  fi
  
  echo ""
  read -p "确认执行同步吗？(y/N) " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

show_stats() {
  echo ""
  echo -e "${CYAN}📊 同步统计${NC}"
  echo "  ─────────────────"
  echo -e "   新增文件: ${GREEN}$STATS_NEW${NC}"
  echo -e "   更新文件: ${YELLOW}$STATS_UPDATED${NC}"
  echo -e "   跳过:     ${BLUE}$STATS_SKIPPED${NC}"
}

# ==========================================
# 主程序
# ==========================================

clear 2>/dev/null || true
echo -e "${GREEN}🔄 Trae 配置同步工具 v3.2${NC}"
echo "============================"
echo "国际版: $TRAE_GLOBAL"
echo "国内版: $TRAE_CN"
echo ""

log "INFO" "===== 同步开始 ====="
log "INFO" "国际版: $TRAE_GLOBAL"
log "INFO" "国内版: $TRAE_CN"

if [ "$DRY_RUN" = true ]; then
  echo -e "${BLUE}🔍 预览模式：只显示会做什么，不实际修改${NC}"
  echo "============================"
  log "INFO" "预览模式"
fi

validate_trae_dir "$TRAE_GLOBAL" "国际版" || true
validate_trae_dir "$TRAE_CN" "国内版" || true

sync_dir "skills"
sync_dir "user_rules"

# MCP 配置和 IDE 设置在 ~/Library/Application Support/ 下
# mcp.json 和 settings.json 需要智能合并（两边各有独有配置，不能简单覆盖）
# 用 Python 解析 JSON 后合并：mcpServers 保留两边的 key，settings 保留两边的配置项
sync_app_json() {
  local file_name="$1"
  local merge_mode="$2"  # "mcp" 或 "settings"
  local global_file="$TRAE_APP_GLOBAL/User/$file_name"
  local cn_file="$TRAE_APP_CN/User/$file_name"
  
  echo ""
  echo -e "${BLUE}📄 同步 $file_name (Application Support)...${NC}"
  
  if [ ! -f "$global_file" ] && [ ! -f "$cn_file" ]; then
    echo -e "   ${YELLOW}ℹ️  两边都没有，跳过${NC}"
    log "INFO" "$file_name: 两边都没有，跳过"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    return
  fi
  
  if [ -f "$global_file" ] && [ ! -f "$cn_file" ]; then
    echo -e "   ⬇️  国际版 -> 国内版（国内版没有）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国内版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      mkdir -p "$TRAE_APP_CN/User"
      cp "$global_file" "$cn_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 从国际版同步到国内版"
    fi
    return
  fi
  
  if [ ! -f "$global_file" ] && [ -f "$cn_file" ]; then
    echo -e "   ⬆️  国内版 -> 国际版（国际版没有）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国际版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      mkdir -p "$TRAE_APP_GLOBAL/User"
      cp "$cn_file" "$global_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 从国内版同步到国际版"
    fi
    return
  fi
  
  global_hash=$(get_file_hash "$global_file")
  cn_hash=$(get_file_hash "$cn_file")
  
  if [ "$global_hash" = "$cn_hash" ] && [ -n "$global_hash" ]; then
    echo -e "   ${GREEN}✅ 内容完全相同，跳过${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    log "INFO" "$file_name: 内容相同，跳过"
    return
  fi
  
  # 两边都有且内容不同：智能合并
  echo -e "   ${YELLOW}⚠️  两边内容不同，智能合并中...${NC}"
  
  if [ "$DRY_RUN" = true ]; then
    # 预览模式：用 Python 显示合并差异
    python3 - "$global_file" "$cn_file" "$merge_mode" --dry-run <<'PYEOF'
import json, sys, re

def load_jsonc(path):
    """加载 JSONC 文件（去除注释和 trailing comma）"""
    with open(path, 'r') as f:
        text = f.read()
    # 去除单行注释（只在行首，不误删 URL 中的 //）
    text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
    # 去除 trailing comma
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text)

global_file, cn_file, merge_mode = sys.argv[1], sys.argv[2], sys.argv[3]
dry_run = '--dry-run' in sys.argv

g = load_jsonc(global_file)
c = load_jsonc(cn_file)

if merge_mode == 'mcp':
    g_servers = set(g.get('mcpServers', {}).keys())
    c_servers = set(c.get('mcpServers', {}).keys())
    only_g = g_servers - c_servers
    only_c = c_servers - g_servers
    common = g_servers & c_servers
    print(f"   国际版独有: {sorted(only_g) if only_g else '无'}")
    print(f"   国内版独有: {sorted(only_c) if only_c else '无'}")
    print(f"   两边共有: {sorted(common) if common else '无'}")
    # 检查共有的 server 配置是否一致
    diff_servers = [s for s in common if json.dumps(g['mcpServers'][s], sort_keys=True) != json.dumps(c['mcpServers'][s], sort_keys=True)]
    if diff_servers:
        print(f"   共有但配置不同: {diff_servers}")
    total = len(g_servers | c_servers)
    print(f"   合并后共 {total} 个 MCP server")
elif merge_mode == 'settings':
    g_keys = set(g.keys())
    c_keys = set(c.keys())
    only_g = g_keys - c_keys
    only_c = c_keys - g_keys
    common = g_keys & c_keys
    print(f"   国际版独有配置: {sorted(only_g) if only_g else '无'}")
    print(f"   国内版独有配置: {sorted(only_c) if only_c else '无'}")
    diff_keys = [k for k in common if json.dumps(g[k], sort_keys=True) != json.dumps(c[k], sort_keys=True)]
    if diff_keys:
        print(f"   共有但值不同: {diff_keys}")
    total = len(g_keys | c_keys)
    print(f"   合并后共 {total} 个配置项")
PYEOF
    echo -e "   ${BLUE}[预览] 合并后两边将拥有彼此的全部配置${NC}"
    STATS_UPDATED=$((STATS_UPDATED + 1))
    return
  fi
  
  # 实际合并
  if [ "$AUTO_YES" = false ]; then
    read -p "   确认智能合并吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "   ${YELLOW}⏭️  已跳过${NC}"
      log "INFO" "$file_name: 用户跳过合并"
      STATS_SKIPPED=$((STATS_SKIPPED + 1))
      return
    fi
  fi
  
  do_backup
  
  # 用 Python 合并 JSON 并写回两个文件
  python3 - "$global_file" "$cn_file" "$merge_mode" <<'PYEOF'
import json, sys, re, os

def load_jsonc(path):
    """加载 JSONC 文件（去除注释和 trailing comma）"""
    with open(path, 'r') as f:
        text = f.read()
    # 去除单行注释（只在行首，不误删 URL 中的 //）
    text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
    # 去除 trailing comma
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text)

def write_json(path, data, indent=2):
    """写回标准 JSON"""
    with open(path, 'w') as f:
        json.dump(data, f, indent=indent, ensure_ascii=False)
        f.write('\n')

global_file, cn_file, merge_mode = sys.argv[1], sys.argv[2], sys.argv[3]

g = load_jsonc(global_file)
c = load_jsonc(cn_file)

if merge_mode == 'mcp':
    # mcp.json: 合并 mcpServers 字典，同名 server 以较新的为准（这里保留 global 侧）
    merged = {'mcpServers': {}}
    # 先放 cn 的
    merged['mcpServers'].update(c.get('mcpServers', {}))
    # 再用 global 的覆盖同名（global 优先）
    merged['mcpServers'].update(g.get('mcpServers', {}))
    # 保留其他顶层字段
    for k, v in g.items():
        if k != 'mcpServers':
            merged[k] = v
    for k, v in c.items():
        if k != 'mcpServers' and k not in merged:
            merged[k] = v
elif merge_mode == 'settings':
    # settings.json: 合并所有顶层 key，冲突时以较新文件的值为准（这里以 global 为主）
    merged = {}
    merged.update(c)  # 先放 cn
    merged.update(g)  # global 覆盖冲突项
else:
    print(f"未知合并模式: {merge_mode}", file=sys.stderr)
    sys.exit(1)

write_json(global_file, merged)
write_json(cn_file, merged)

# 统计变化
if merge_mode == 'mcp':
    total = len(merged.get('mcpServers', {}))
    print(f"   合并后共 {total} 个 MCP server")
else:
    total = len(merged)
    print(f"   合并后共 {total} 个配置项")
PYEOF
  
  echo -e "   ${GREEN}✅ 已智能合并（两边都已更新为合并后的内容）${NC}"
  STATS_UPDATED=$((STATS_UPDATED + 1))
  log "INFO" "$file_name: 智能合并完成"
}

sync_app_json "mcp.json" "mcp"
sync_app_json "settings.json" "settings"

# skill-config.json 在 ~/.trae 下，也用智能合并
sync_skill_config() {
  local file_name="skill-config.json"
  local global_file="$TRAE_GLOBAL/$file_name"
  local cn_file="$TRAE_CN/$file_name"
  
  echo ""
  echo -e "${BLUE}📄 同步 $file_name...${NC}"
  
  if [ ! -f "$global_file" ] && [ ! -f "$cn_file" ]; then
    echo -e "   ${YELLOW}ℹ️  两边都没有，跳过${NC}"
    log "INFO" "$file_name: 两边都没有，跳过"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    return
  fi
  
  if [ -f "$global_file" ] && [ ! -f "$cn_file" ]; then
    echo -e "   ⬇️  国际版 -> 国内版"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国内版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      cp "$global_file" "$cn_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 从国际版同步到国内版"
    fi
    return
  fi
  
  if [ ! -f "$global_file" ] && [ -f "$cn_file" ]; then
    echo -e "   ⬆️  国内版 -> 国际版"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国际版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      cp "$cn_file" "$global_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 从国内版同步到国际版"
    fi
    return
  fi
  
  global_hash=$(get_file_hash "$global_file")
  cn_hash=$(get_file_hash "$cn_file")
  
  if [ "$global_hash" = "$cn_hash" ] && [ -n "$global_hash" ]; then
    echo -e "   ${GREEN}✅ 内容完全相同，跳过${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    log "INFO" "$file_name: 内容相同，跳过"
    return
  fi
  
  # 内容不同：智能合并
  echo -e "   ${YELLOW}⚠️  两边内容不同，智能合并中...${NC}"
  
  if [ "$DRY_RUN" = true ]; then
    python3 - "$global_file" "$cn_file" --dry-run <<'PYEOF'
import json, sys
g = json.load(open(sys.argv[1]))
c = json.load(open(sys.argv[2]))
g_keys = set(g.keys())
c_keys = set(c.keys())
only_g = g_keys - c_keys
only_c = c_keys - g_keys
common = g_keys & c_keys
print(f"   国际版独有: {sorted(only_g) if only_g else '无'}")
print(f"   国内版独有: {sorted(only_c) if only_c else '无'}")
diff_keys = [k for k in common if json.dumps(g[k], sort_keys=True) != json.dumps(c[k], sort_keys=True)]
if diff_keys:
    print(f"   共有但值不同: {diff_keys}")
total = len(g_keys | c_keys)
print(f"   合并后共 {total} 个配置项")
PYEOF
    echo -e "   ${BLUE}[预览] 合并后两边将拥有彼此的全部配置${NC}"
    STATS_UPDATED=$((STATS_UPDATED + 1))
    return
  fi
  
  if [ "$AUTO_YES" = false ]; then
    read -p "   确认智能合并吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "   ${YELLOW}⏭️  已跳过${NC}"
      log "INFO" "$file_name: 用户跳过合并"
      STATS_SKIPPED=$((STATS_SKIPPED + 1))
      return
    fi
  fi
  
  do_backup
  
  python3 - "$global_file" "$cn_file" <<'PYEOF'
import json, sys

global_file, cn_file = sys.argv[1], sys.argv[2]
g = json.load(open(global_file))
c = json.load(open(cn_file))

merged = {}
merged.update(c)
merged.update(g)

with open(global_file, 'w') as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)
    f.write('\n')
with open(cn_file, 'w') as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"   合并后共 {len(merged)} 个配置项")
PYEOF
  
  echo -e "   ${GREEN}✅ 已智能合并${NC}"
  STATS_UPDATED=$((STATS_UPDATED + 1))
  log "INFO" "$file_name: 智能合并完成"
}

sync_skill_config

show_stats

echo ""
echo "============================"

if [ "$DRY_RUN" = true ]; then
  echo -e "${BLUE}🔍 预览完成，没有实际修改${NC}"
  echo ""
  echo "确认没问题的话，去掉 -n 参数真正执行："
  echo "  ~/sync-trae-config.sh"
  log "INFO" "预览完成"
else
  if confirm; then
    echo -e "${GREEN}✅ 同步完成${NC}"
    if [ "$BACKUP_DONE" = true ] && [ -d "$BACKUP_DIR" ]; then
      echo -e "💾 备份位置: $BACKUP_DIR"
    fi
    echo -e "📝 日志文件: $LOG_FILE"
    log "INFO" "同步完成"
  else
    echo -e "${YELLOW}⏹️  已取消，没有修改任何文件${NC}"
    log "INFO" "用户取消了同步"
  fi
fi

log "INFO" "===== 同步结束 ====="
echo ""
