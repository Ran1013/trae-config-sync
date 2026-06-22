#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRAE_GLOBAL="$HOME/.trae"
TRAE_CN="$HOME/.trae-cn"
BACKUP_ROOT="$SCRIPT_DIR/backups"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$SCRIPT_DIR/sync.log"
DRY_RUN=false
AUTO_YES=false
BACKUP_DONE=false
STATS_NEW=0
STATS_UPDATED=0
STATS_SKIPPED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  local level="$1"
  shift
  local msg="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

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
      echo "🧹 清理 7 天前的旧备份..."
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
      exit 0
      ;;
    *)
      echo "未知选项: $1"
      echo "使用 --help 查看帮助"
      exit 1
      ;;
  esac
done

mkdir -p "$BACKUP_ROOT"

validate_trae_dir() {
  local dir="$1"
  local name="$2"
  if [ ! -d "$dir" ]; then
    echo -e "${YELLOW}⚠️  $name 目录不存在: $dir${NC}"
    log "WARN" "$name 目录不存在: $dir"
    return 1
  fi
  if [ -d "$dir/skills" ] || [ -d "$dir/rules" ] || [ -f "$dir/mcp.json" ]; then
    return 0
  fi
  echo -e "${YELLOW}⚠️  $name 目录看起来不像 Trae 配置目录${NC}"
  if [ "$AUTO_YES" = false ]; then
    read -p "   还要继续吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "已取消"
      exit 1
    fi
  fi
  return 0
}

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
  if [ -d "$TRAE_GLOBAL" ]; then
    cp -RL "$TRAE_GLOBAL" "$BACKUP_DIR/trae-global" 2>/dev/null || true
    log "INFO" "已备份国际版配置"
  fi
  if [ -d "$TRAE_CN" ]; then
    cp -RL "$TRAE_CN" "$BACKUP_DIR/trae-cn" 2>/dev/null || true
    log "INFO" "已备份国内版配置"
  fi
  BACKUP_DONE=true
  echo -e "${GREEN}💾 备份已创建: $BACKUP_DIR${NC}"
  log "INFO" "备份创建完成: $BACKUP_DIR"
}

get_file_hash() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo ""
    return
  fi
  md5 -q "$file" 2>/dev/null || echo ""
}

get_latest_mtime() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi
  local latest=$(find "$dir" -type f -not -type l -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1)
  if [ -z "$latest" ]; then
    echo 0
  else
    echo "$latest" | awk '{print $1}'
  fi
}

count_files() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi
  find "$dir" -type f -not -type l 2>/dev/null | wc -l | tr -d ' '
}

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
    return
  fi

  if [ -d "$global_dir" ] && [ ! -d "$cn_dir" ]; then
    echo -e "   ⬇️  国际版 → 国内版（国内版没有）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $dir_name 到国内版${NC}"
      STATS_NEW=$((STATS_NEW + global_count))
    else
      do_backup
      mkdir -p "$TRAE_CN"
      cp -r "$global_dir" "$cn_dir"
      echo -e "   ${GREEN}✅ 已同步（新增 $global_count 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + global_count))
      log "INFO" "$dir_name: 国际版→国内版，新增 $global_count 个文件"
    fi
    return
  fi

  if [ ! -d "$global_dir" ] && [ -d "$cn_dir" ]; then
    echo -e "   ⬆️  国内版 → 国际版（国际版没有）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $dir_name 到国际版${NC}"
      STATS_NEW=$((STATS_NEW + cn_count))
    else
      do_backup
      mkdir -p "$TRAE_GLOBAL"
      cp -r "$cn_dir" "$global_dir"
      echo -e "   ${GREEN}✅ 已同步（新增 $cn_count 个文件）${NC}"
      STATS_NEW=$((STATS_NEW + cn_count))
      log "INFO" "$dir_name: 国内版→国际版，新增 $cn_count 个文件"
    fi
    return
  fi

  global_mtime=$(get_latest_mtime "$global_dir")
  cn_mtime=$(get_latest_mtime "$cn_dir")

  if [ "$global_mtime" -gt "$cn_mtime" ]; then
    echo -e "   ⬇️  国际版 → 国内版（国际版更新）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将从国际版新增文件到国内版${NC}"
    else
      do_backup
      local before=$(count_files "$cn_dir")
      cp -rn "$global_dir"/* "$cn_dir/" 2>&1 | grep -v "omitting directory" || true
      local after=$(count_files "$cn_dir")
      local added=$((after - before))
      if [ "$added" -gt 0 ]; then
        echo -e "   ${GREEN}✅ 已同步（新增 $added 个文件）${NC}"
        STATS_NEW=$((STATS_NEW + added))
      else
        echo -e "   ${YELLOW}ℹ️  没有新文件需要同步${NC}"
        STATS_SKIPPED=$((STATS_SKIPPED + 1))
      fi
      log "INFO" "$dir_name: 国际版→国内版，新增 $added 个文件"
    fi
  elif [ "$cn_mtime" -gt "$global_mtime" ]; then
    echo -e "   ⬆️  国内版 → 国际版（国内版更新）"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将从国内版新增文件到国际版${NC}"
    else
      do_backup
      local before=$(count_files "$global_dir")
      cp -rn "$cn_dir"/* "$global_dir/" 2>&1 | grep -v "omitting directory" || true
      local after=$(count_files "$global_dir")
      local added=$((after - before))
      if [ "$added" -gt 0 ]; then
        echo -e "   ${GREEN}✅ 已同步（新增 $added 个文件）${NC}"
        STATS_NEW=$((STATS_NEW + added))
      else
        echo -e "   ${YELLOW}ℹ️  没有新文件需要同步${NC}"
        STATS_SKIPPED=$((STATS_SKIPPED + 1))
      fi
      log "INFO" "$dir_name: 国内版→国际版，新增 $added 个文件"
    fi
  else
    echo -e "   ${YELLOW}ℹ️  两边一样新，跳过${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    log "INFO" "$dir_name: 两边一样新，跳过"
  fi
}

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
    echo -e "   ⬇️  国际版 → 国内版"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国内版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      mkdir -p "$TRAE_CN"
      cp "$global_file" "$cn_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 国际版→国内版"
    fi
    return
  fi

  if [ ! -f "$global_file" ] && [ -f "$cn_file" ]; then
    echo -e "   ⬆️  国内版 → 国际版"
    if [ "$DRY_RUN" = true ]; then
      echo -e "   ${BLUE}[预览] 将复制 $file_name 到国际版${NC}"
      STATS_NEW=$((STATS_NEW + 1))
    else
      do_backup
      mkdir -p "$TRAE_GLOBAL"
      cp "$cn_file" "$global_file"
      echo -e "   ${GREEN}✅ 已同步${NC}"
      STATS_NEW=$((STATS_NEW + 1))
      log "INFO" "$file_name: 国内版→国际版"
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
    echo -e "   ⬇️  国际版 → 国内版（国际版更新）"
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
      log "INFO" "$file_name: 国际版覆盖国内版"
    fi
  elif [ "$cn_mtime" -gt "$global_mtime" ]; then
    echo -e "   ⬆️  国内版 → 国际版（国内版更新）"
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
      log "INFO" "$file_name: 国内版覆盖国际版"
    fi
  else
    echo -e "   ${YELLOW}ℹ️  时间相同但内容不同，请手动合并${NC}"
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    log "WARN" "$file_name: 时间相同但内容不同，需手动合并"
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

clear
echo -e "${GREEN}🔄 Trae 配置同步工具 v3.1${NC}"
echo "============================"
echo "国际版: $TRAE_GLOBAL"
echo "国内版: $TRAE_CN"
echo ""
echo "📁 项目目录: $SCRIPT_DIR"
echo "💾 备份目录: $BACKUP_ROOT"
echo "📝 日志文件: $LOG_FILE"

log "INFO" "===== 同步开始 ====="
log "INFO" "国际版: $TRAE_GLOBAL"
log "INFO" "国内版: $TRAE_CN"

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo -e "${BLUE}🔍 预览模式：只显示会做什么，不实际修改${NC}"
  echo "============================"
  log "INFO" "预览模式"
fi

validate_trae_dir "$TRAE_GLOBAL" "国际版" || true
validate_trae_dir "$TRAE_CN" "国内版" || true

sync_dir "skills"
sync_dir "rules"
sync_file "mcp.json"

show_stats

echo ""
echo "============================"

if [ "$DRY_RUN" = true ]; then
  echo -e "${BLUE}🔍 预览完成，没有实际修改${NC}"
  echo ""
  echo "确认没问题的话，去掉 -n 参数真正执行："
  echo "  ./sync-trae-config.sh"
  log "INFO" "预览完成"
else
  if confirm; then
    echo -e "${GREEN}✅ 同步完成${NC}"
    if [ "$BACKUP_DONE" = true ] && [ -d "$BACKUP_DIR" ]; then
      echo -e "💾 备份位置: $BACKUP_DIR"
    fi
    log "INFO" "同步完成"
  else
    echo -e "${YELLOW}⏹️  已取消，没有修改任何文件${NC}"
    log "INFO" "用户取消了同步"
  fi
fi

log "INFO" "===== 同步结束 ====="
echo ""
