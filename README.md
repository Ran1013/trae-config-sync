# 🔄 Trae Config Sync

> Trae 国际版 ↔ 国内版 配置双向同步工具

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#)
[![Version](https://img.shields.io/badge/version-3.1-brightgreen.svg)](#)

## ✨ 功能特性

- 🔄 **双向智能同步** - 自动比较时间戳，从较新的一方向另一方同步
- 📦 **只同步配置** - Skills、Rules、MCP 配置，不碰历史记录
- 💾 **自动备份** - 同步前自动备份，出问题随时能恢复
- 🔍 **预览模式** - 先看会改什么，确认没问题再执行
- 📊 **同步统计** - 清晰显示新增、更新、跳过的文件数量
- 📝 **操作日志** - 所有操作记录到日志，方便事后审计
- 🛡️ **安全确认** - 覆盖文件前二次确认，防止误操作
- 🧹 **备份清理** - 一键清理 7 天前的旧备份
- 📁 **单目录设计** - 所有东西都在一个文件夹，不用了直接删

## 🚀 快速开始

### 环境要求

- macOS（已测试）
- Bash 3.2+
- 已安装 Trae 国际版和/或国内版

### 安装

```bash
# 克隆仓库
git clone https://github.com/你的用户名/trae-config-sync.git
cd trae-config-sync

# 加执行权限
chmod +x *.sh
```

### 基本使用

**1. 先预览（推荐！）**

```bash
./sync-trae-config.sh --dry-run
# 或简写
./sync-trae-config.sh -n
```

**2. 确认没问题后，真正同步**

```bash
./sync-trae-config.sh
```

**3. 自动确认（适合熟练后使用）**

```bash
./sync-trae-config.sh --yes
# 或简写
./sync-trae-config.sh -y
```

## 📖 完整用法

### 命令选项

| 选项 | 简写 | 说明 |
|------|------|------|
| `--dry-run` | `-n` | 预览模式，只显示不执行 |
| `--yes` | `-y` | 自动确认，不询问用户 |
| `--clean` | - | 清理 7 天前的旧备份 |
| `--help` | `-h` | 显示帮助信息 |

### 同步内容

| 配置项 | 说明 | 同步策略 |
|--------|------|---------|
| Skills | 技能目录 | 只新增，不覆盖已有文件 |
| Rules | 规则目录 | 只新增，不覆盖已有文件 |
| MCP | MCP 配置文件 | 内容不同时提示确认覆盖 |

### 配置路径

| 版本 | 用户配置目录 |
|------|-------------|
| 国际版 | `~/.trae/` |
| 国内版 | `~/.trae-cn/` |

## 📁 项目结构

```
trae-config-sync/
├── sync-trae-config.sh    # 主脚本
├── setup.sh               # 一键初始化 git
├── push.sh                # 推送到 GitHub
├── uninstall.sh           # 一键卸载
├── README.md              # 说明文档
├── LICENSE                # 开源协议
├── .gitignore             # git 忽略规则
├── backups/               # 备份目录（同步时自动创建）
│   └── 20240622_103000/
└── sync.log               # 操作日志
```

## 🎯 使用场景

### 场景一：平时配置同步

```bash
# 在国际版加了新 Rule，想同步到国内版
./sync-trae-config.sh -n  # 先预览
./sync-trae-config.sh     # 确认后同步
```

### 场景二：换新电脑

```bash
# 从备份恢复配置
cp -r backups/某个时间点/trae-global ~/.trae
cp -r backups/某个时间点/trae-cn ~/.trae-cn
```

### 场景三：定期清理旧备份

```bash
# 清理 7 天前的旧备份
./sync-trae-config.sh --clean
```

### 场景四：不想用了，一键卸载

```bash
./uninstall.sh
```

## 🛡️ 安全机制

1. **目录验证** - 启动时检查目录是否真的是 Trae 配置
2. **预览模式** - 先看后做，避免意外
3. **自动备份** - 同步前完整备份两边配置
4. **二次确认** - 覆盖文件前询问用户
5. **操作日志** - 所有操作可追溯
6. **内容校验** - 用 MD5 比较文件内容，避免无意义的覆盖
7. **单目录设计** - 所有文件都在一个目录，方便管理和清理

## ❓ 常见问题

### Q: 会同步历史记录吗？

不会。只同步 Skills、Rules、MCP 配置，历史记录、缓存、登录信息都不会动。

### Q: 两边配置不一样，会覆盖吗？

- 对于目录（Skills、Rules）：只新增文件，不会覆盖已有文件
- 对于文件（mcp.json）：会提示确认，你可以选择覆盖或跳过

### Q: 同步出错了怎么办？

每次同步前都会自动备份到 `backups/` 目录，从备份恢复就行。

### Q: 支持 Linux/Windows 吗？

目前只在 macOS 上测试过。Linux 应该可以用，Windows 需要 WSL。

### Q: 能同步其他配置吗？

目前只支持 Skills、Rules、MCP。如果你需要同步其他配置，可以提 Issue 或者自己改脚本。

### Q: 怎么卸载？

直接运行 `./uninstall.sh`，或者手动删除整个目录就行。

## 🤝 贡献

欢迎贡献代码！请遵循以下步骤：

1. Fork 本仓库
2. 创建你的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交你的改动 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启一个 Pull Request

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- 感谢 Trae 团队做出这么棒的 AI IDE
- 感谢所有为这个项目贡献代码的人

---

**如果这个工具对你有帮助，别忘了给个 ⭐ Star 哦！**
