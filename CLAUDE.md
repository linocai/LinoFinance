# LinoFinance · 项目工作规范与经验

> 本文件只放**本项目专属**的工程经验与坑。通用的跨项目原则（含 Apple 工程通用坑）在全局 `~/.claude/CLAUDE.md`，不在此重复。
> 计划唯一权威是 [PROJECT_PLAN.md](PROJECT_PLAN.md)（上半生效 plan / 下半变更日志）。**不要再新建 state / audit / plan_v2 类文件**；`.planning/` 已退役（仅留 `screenshots/`），历史 plan 全文在 `archive/`。
> **`PROJECT_PLAN.md` 与 `archive/` 已于 2026-06-12 由用户决定改为本地不跟踪**（写入 `.gitignore` 并 `git rm --cached` 摘出索引）。它们仍是计划的唯一权威，但只存在于本地工作区，不进 git 历史 / 远端；别再尝试把它们 `git add` / commit 回版本控制。

## 工作流

实质施工走全局三段式（@planner → @builder → @reviewer），全部写进 PROJECT_PLAN.md。

**git 工作流（2026-06-12 起改）：直接在 `main` 上提交，不再建 `release/vX.Y.Z` 分支、不再走 PR。** v1.0–v1.3 历史上用过 release 分支 + PR，已于 v1.3.0 发布后由用户决定简化为 main 直提（旧 release 分支已清理，远端只剩 `main`）。版本 tag 习惯**保留**：发版时在 `main` 对应提交打 `vX.Y.Z` tag 作回滚锚点。**tag / push / live 部署一律由用户手动执行**——builder 只在本地 `main` 提交，不 push、不打 tag、不部署。

## 仓库结构速记

- `backend/` FastAPI 应用（`app/`），Alembic（`alembic/versions/`），测试 `tests/`，脚本 `scripts/`。venv 在 `backend/.venv`（gitignore）。
- `frontend/` Xcode 工程 `LinoFinance.xcodeproj`，**两 target**（2026-06-14 v1 已整删）：多平台 App `LinoFinanceV2`（product `LinoF2`，显示名 `LinoF`，源在 `frontend/LinoFinanceV2/`，bundle `com.lino.linofinance`，部署 macOS 26.0/iOS 26.0）+ widget `LinoFinanceV2Widgets`（`frontend/LinoFinanceV2Widgets/`，bundle `com.lino.linofinance.widgets`）。
  - **共享 Core 6 文件在中性目录 `frontend/Core/`**（`LinoAPIClient`/`SecureTokenStore`/`APIDTOs`/`APIRequests`/`FinanceRepository`/`Formatters`）：以 `SOURCE_ROOT` `PBXFileReference` 编入 v2 app target（非同步组、非拷贝）。**历史上它们躺在 v1 的 `LinoFinance/Core/` 里被 v2 借用,删 v1 时迁出到 `frontend/Core/`。**
  - **老三 target（v1.4.0 macOS `LinoFinance`/iOS `LinoFinanceiOS`/`LinoFinanceWidgets`）+ SwiftPM(`Package.swift`/`Sources`/`Tests`)已于 2026-06-14 整删**（自用简化,v2 已上线顶替）；如需 v1 源码,git tag `v1.3.0` 可找回。`swift test` 编译护栏随 SPM 一并退役。

## pbxproj（objectVersion 77 折叠同步工程）

- 本工程是**手写 objectVersion 77** pbxproj，用 `PBXFileSystemSynchronizedRootGroup` 文件夹同步（不是逐文件 reference）：每个 target `fileSystemSynchronizedGroups` 指一个源文件夹，整夹自动入编译。改它**不要手撸 UUID**。
- 可靠手段：`xcodeproj` Ruby gem（`gem install xcodeproj --user-install`，1.27.0 支持 v77 + 同步组）。**系统 ruby 2.6 必须强制 UTF-8**：`LANG/LC_ALL=en_US.UTF-8 RUBYOPT="-Eutf-8" GEM_HOME=~/.gem/ruby/2.6.0`，否则读 pbxproj 中文 INFOPLIST 键报 `invalid byte sequence in US-ASCII`。
- gem 坑：`PBXNativeTarget`/同步组的 to-many 关系（`file_system_synchronized_groups`、`exceptions`）**无 `=` setter，用 `<<`**；`proj.new(PBXNativeTarget)` **不自动建 `build_configuration_list`**，要手建 `XCConfigurationList`+Debug/Release `XCBuildConfiguration`。
- 跨 target 共享单个文件（非整夹）：建普通 `PBXFileReference`（`source_tree=SOURCE_ROOT`，path 指中性 `frontend/Core/` 内文件）+ `PBXBuildFile` 塞进目标 target 的 Sources phase——与同步组并存合法。**搬移这些共享文件只需 `git mv` + 改 `PBXFileReference` 的 `path` 字符串**（build file 自动跟随,v2 编译集不变；非 UUID 手术,安全）。删 target / sync group 才需 `xcodeproj` gem。
- 安全流程（已验证零破坏）：改前 `cp project.pbxproj project.pbxproj.bak-<UTC>`；先 no-op open+save round-trip（churn 仅补空 `exceptions=()`/删空 `packageProductDependencies=()`，无害）+ 临时副本跑脚本 dry-run；落真工程后立即 `xcodebuild -list` + v2 macOS/iOS target 复测 BUILD SUCCEEDED 再继续。**注：临时副本因 SOURCE_ROOT 错位不能直接 build 验源码，只验结构；源码编译验证在真工程原地做。**
- `docs/` 参考文档（`api-contract.md` / `deployment.md`）。`deploy/` systemd + nginx 示例。`scripts/deploy-api.sh` 部署脚本。

## 构建 & 测试

```bash
# 后端
cd backend && source .venv/bin/activate
.venv/bin/pytest            # 当前 162 通过（main = v2.0.0，已发布部署）
.venv/bin/ruff check .
.venv/bin/alembic upgrade head
python scripts/run_local_sqlite.py     # 本地 SQLite API，端口 6868

# 前端（仅 v2 两 target；SwiftPM/swift test 已退役）
cd frontend
xcodebuild -project LinoFinance.xcodeproj -scheme LinoFinanceV2 \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
# iOS 验证：-destination 'generic/platform=iOS Simulator'（或具名 iPhone 17/OS=26.5）
# CODE_SIGNING_ALLOWED=NO：v2 entitlements 含 App Group/aps/SIWA,三 capability 须开发者后台
#   为正式 id（com.lino.linofinance / .widgets）注册才能签名；注册前本地签名会失败。
#   模拟器 build 本就不签名、可不加。已签好的 macOS Release 已装 /Applications/LinoF.app。
```

## 前端铁律

- **业务 UI + DesignSystem 在 Xcode target `frontend/LinoFinanceV2/`**；跨 target 共享的网络/模型/仓储 Core 6 文件在 `frontend/Core/`（见仓库结构速记）。**SwiftPM 已退役**（2026-06-14 随 v1 整删）——不再有 `swift test`，前端唯一编译门禁是 `xcodebuild`。
- 新增只被 app target 用的 DTO / request 类型放 `frontend/LinoFinanceV2/`（或共享则放 `frontend/Core/Models/`）；编码正确性由后端 local smoke + `xcodebuild` 联合验证。
- 改 SwiftUI View 必须用 `xcodebuild` 跑 v2 target 验证;液态玻璃/侧栏/双币种等 View 层效果须真机/真模拟器目视(单测抓不到)。

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
- 付费 Apple 团队 Team ID `HX73DFL88G`；改 team 要同步 pbxproj 里 4 处 `DEVELOPMENT_TEAM`（v2 app + widget × Debug/Release）。真机签名走 automatic signing。
- **bundle id 现状（v1 已删,只剩 v2 两 target）**：app = `com.lino.linofinance`（macOS 顶替线上 v1 原地升级；iOS 与已下线的 v1 `.ios` 不同 id → 是新 app）；widget = `com.lino.linofinance.widgets`；App Group = `group.com.lino.linofinance`（entitlements + `V2WidgetSnapshot`/`WidgetsBundle` 常量）。`aps-environment` 暂留 development（真正 Archive 上架时翻 production）。**App Group/SIWA/Push capability 须用户在开发者后台为正式 id 注册才能签名**（注册前本地 v2 构建须 `CODE_SIGNING_ALLOWED=NO`）；macOS 已有签好的 Release 装在 `/Applications/LinoF.app`。
- 版本号源（发版统一改）：`backend/pyproject.toml`、`backend/app/core/config.py` 的 `app_version`、`scripts/deploy-api.sh` 的 `EXPECTED_VERSION`、pbxproj 里 8 处（`MARKETING_VERSION` 4 + `CURRENT_PROJECT_VERSION` 4）。
- 范围铁律：只动 LinoFinance，不碰 hz 上的 LA / Qbot / 主页 / 100j。

## 真机验证

依赖真签名/真容器/真系统环境的行为（启动期 AMFI、keychain ACL、APNs 真推、Apple 登录闭环）单测一律抓不到。这些项 builder 在本环境做不了，照实留给用户自理并写进 PROJECT_PLAN 的「用户侧收尾」。`notarize`/`codesign --verify` 通过 ≠ 能启动。
