# LinoFinance · 项目工作规范与经验

> 本文件只放**本项目专属**的工程经验与坑。通用的跨项目原则（含 Apple 工程通用坑）在全局 `~/.claude/CLAUDE.md`，不在此重复。
> 计划唯一权威是 [PROJECT_PLAN.md](PROJECT_PLAN.md)（上半生效 plan / 下半变更日志）。**不要再新建 state / audit / plan_v2 类文件**；`.planning/` 已退役（仅留 `screenshots/`），历史 plan 全文在 `archive/`。

## 工作流

实质施工走全局三段式（@planner → @builder → @reviewer），全部写进 PROJECT_PLAN.md。

**git 工作流（2026-06-12 起改）：直接在 `main` 上提交，不再建 `release/vX.Y.Z` 分支、不再走 PR。** v1.0–v1.3 历史上用过 release 分支 + PR，已于 v1.3.0 发布后由用户决定简化为 main 直提（旧 release 分支已清理，远端只剩 `main`）。版本 tag 习惯**保留**：发版时在 `main` 对应提交打 `vX.Y.Z` tag 作回滚锚点。**tag / push / live 部署一律由用户手动执行**——builder 只在本地 `main` 提交，不 push、不打 tag、不部署。

## 仓库结构速记

- `backend/` FastAPI 应用（`app/`），Alembic（`alembic/versions/`），测试 `tests/`，脚本 `scripts/`。venv 在 `backend/.venv`（gitignore）。
- `frontend/` Xcode 工程 `LinoFinance.xcodeproj` + SwiftPM `Package.swift`。三 target：macOS `LinoFinance`、iOS `LinoFinanceiOS`（product `LinoF`，bundle `com.lino.linofinance.ios`）、widget `LinoFinanceWidgets`。
- `docs/` 参考文档（`api-contract.md` / `deployment.md`）。`deploy/` systemd + nginx 示例。`scripts/deploy-api.sh` 部署脚本。

## 构建 & 测试

```bash
# 后端
cd backend && source .venv/bin/activate
.venv/bin/pytest            # 当前 113 通过
.venv/bin/ruff check .
.venv/bin/alembic upgrade head
python scripts/run_local_sqlite.py     # 本地 SQLite API，端口 6868

# 前端
cd frontend && swift test   # 16 通过；仅覆盖 SPM 共享库，不含 Xcode target 业务 UI
xcodebuild -project frontend/LinoFinance.xcodeproj -scheme LinoFinance \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath frontend/.derivedData build
# iOS 验证（确认模拟器 runtime 可用，历史上本机一度只有不可用的 iPhone Air iOS 26.4）：
#   -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.4.1'
```

## 前端铁律

- **业务 UI 在 Xcode target `frontend/LinoFinance/`，不在 SwiftPM**。SwiftPM `frontend/Sources/*` 只放共享库 + 编译型测试。
- 新增只被 Xcode target 用的 DTO / request 类型放 `frontend/LinoFinance/Core/Models/`，**不要镜像进 SPM `LinoFinanceCore`**——`swift test` 看不到 Xcode target 源码，硬塞只能测重复 stub。这类编码正确性由后端 local smoke + xcodebuild 联合验证（v1.1.7 P2、v1.2 P4 已两次按此判断跳过 SPM 编码测试，照实写进变更日志偏离）。
- 改 SwiftUI View 必须用 `xcodebuild` 跑 App target 验证；只跑 `swift test` 不暴露 View 层问题。

## 后端铁律

- **Python 3.9**（`ruff target-version = py39`，venv 也是 3.9）。代码保持 3.9 兼容。
- 任何模型变更：Alembic 迁移 + 更新 `docs/api-contract.md` + happy/failure 双测试。
- **SQLite 偏差**（本地 runner 用 SQLite，生产 Postgres）：
  - Postgres 专属的 partial index 用 `if op.get_bind().dialect.name == "postgresql": …` 守卫；
  - 级联删除靠 `PRAGMA foreign_keys=ON` 才在 SQLite 生效；
  - `Numeric(18,8)` 在 API 输出会带数据库 scale（`6.80000000`），需在 schema 层裁掉尾零（产品口径 `6.8`）；
  - py39 下 `date: Mapped[date]` 会让字段名 shadow 掉 `date` 类型 → 用 `from datetime import date as DateType`。
- 新建 venv：先升 `pip/setuptools/wheel` 再 `pip install -e ".[dev]"`（老 pip 不支持 PEP 660）；flat-layout 用 `include = ["app*"]` 避免 setuptools 把 `alembic` 也当顶层包。

## 鉴权

- 两条路：Apple 会话 token（哈希存 `auth_sessions`）或 admin 环境 token `LINOFINANCE_API_AUTH_TOKEN`（运维旁路，保留）。线头 `Authorization: Bearer <token>` 两者通用。
- 中间件：会话库不可达/任何异常**一律返回干净 401**（不暴露 500）；交付给请求的 session/user 是 `expunge` 后的游离对象，**注销/撤销要在路由自己的 DB session 上落库**（直接改游离对象不持久化）。
- 客户端 Keychain 双槽：`linofinance.sessionToken`（Apple 登录）/ `linofinance.adminToken`（手动 admin）。
- `LINOFINANCE_APPLE_DEV_SHORTCUT`：仅非生产可跳过 JWKS 验证（identity_token 原样当 `sub`），生产启动期 `validate_runtime` 强制拒绝。

## 部署 & 发版

- 生产 `hz`：`deploy@118.178.122.194`，release 路径 `/opt/linofinance/app/current`（软链），systemd `linofinance-api`，env `/etc/linofinance/api.env`（`root:linofinance` `640`），域名 `https://lf.linotsai.top/api/v1`。详见 [docs/deployment.md](docs/deployment.md) 与 `~/HZ云使用手册.md`。
- 部署前 `scripts/deploy-api.sh --dry-run` 必须干净。**live 部署 / tag / push 由用户手动**。
- **macOS 装机路径是 `/Applications/LinoF.app`**（历史 v1.1.5/6 plan 一度误写 `/Users/linotsai/Applications/...`，别再犯）。换包前旧 bundle 备份成 `LinoF.app.bak-<UTC>`。拷 `.app` 用 `ditto` 不用 `cp -R`。
- 付费 Apple 团队 Team ID `HX73DFL88G`；改 team 要同步 pbxproj 里 4 处 `DEVELOPMENT_TEAM`。真机签名走 automatic signing。
- 版本号源（发版统一改）：`backend/pyproject.toml`、`backend/app/core/config.py` 的 `app_version`、`scripts/deploy-api.sh` 的 `EXPECTED_VERSION`、pbxproj 里 12 处 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`。
- 范围铁律：只动 LinoFinance，不碰 hz 上的 LA / Qbot / 主页 / 100j。

## 真机验证

依赖真签名/真容器/真系统环境的行为（启动期 AMFI、keychain ACL、APNs 真推、Apple 登录闭环）单测一律抓不到。这些项 builder 在本环境做不了，照实留给用户自理并写进 PROJECT_PLAN 的「用户侧收尾」。`notarize`/`codesign --verify` 通过 ≠ 能启动。
