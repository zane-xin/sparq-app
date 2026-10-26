# Sparq App

`sparq-app` 是 Sparq 默认壳，负责默认启动入口、运行配置和本地运行数据。

## 目录

```text
cmd/sparq/                # 默认启动入口和生成的本地插件 Bundle 装配文件
config/                   # 默认 app 和 plugins 配置
public/admin/             # 构建后的 Admin Shell 静态资源
public/assets/            # 公开静态资源
run/                      # 宿主控制通道和插件进程运行文件（运行时创建）
storage/database/         # SQLite 数据库（运行时创建）
storage/logs/             # 应用日志
plugins/                  # 当前激活的 ManagedProcess 插件包
themes/                   # 已安装主题，目录名为 <code>@<version>
storage/uploads/public/   # 公开上传资源
storage/uploads/private/  # 私有上传资源，不直接暴露
plugins/.staging/         # 插件更新临时目录
storage/tmp/uploads/      # 分片上传临时目录
storage/tmp/themes/       # 主题下载和解压临时目录
```

## 启动

从仓库根目录运行：

```bash
go run ./sparq-app/cmd/sparq
```

构建后运行：

```bash
make build
./bin/sparq
```

也可以在 `sparq-app` 目录内运行：

```bash
cd sparq-app
go run ./cmd/sparq
```

## 同时开发后端和 Admin Shell

保留 `sparq-app/` 与 `sparq-admin/` 两个独立仓库，由 [sparq.dev.yaml](sparq.dev.yaml) 指定后端监听配置和 Shell 源码路径。默认后端为 `http://127.0.0.1:19090`，Shell 为 `http://127.0.0.1:5188`，API 请求由 Shell 代理到后端。默认壳没有自己的业务前端，所以 `frontend.mode` 为 `disabled`。

以下命令均从包含 `sparq-app/`、`sparq-admin/` 和 `sparq-tool/` 的开发 workspace 根目录执行。先安装 Shell 依赖：

```bash
pnpm --dir sparq-admin install
```

如果实例尚未安装，先单独启动后端：

```bash
go run ./sparq-app/cmd/sparq serve --root sparq-app --config config/app.yaml --env dev --addr 127.0.0.1:19090
```

访问 `http://127.0.0.1:19090/`，按页面提示进入 `/__install__` 完成安装，然后 Ctrl+C 停止后端。联调使用运行态 `/__healthz__` 判断后端就绪；安装阶段尚无该接口，不能直接等待联调命令完成安装。

检查执行计划，再启动联调：

```bash
make dev-app-plan
make dev-app
```

根目录 Makefile 会先构建当前源码的工具，也可直接使用源码入口：

```bash
go run ./sparq-tool/cmd/sparq-tool dev app --file sparq-app/sparq.dev.yaml --dry-run
go run ./sparq-tool/cmd/sparq-tool dev app --file sparq-app/sparq.dev.yaml
```

`--dry-run` 仅校验配置、路径和启动顺序，不启动服务或检查端口占用。正式启动会先构建并等待后端健康检查，再启动 Shell；看到就绪提示后访问 `http://127.0.0.1:5188`。工具显式注入 API 代理，覆盖 Shell `.env` 中的旧地址。Ctrl+C 或任一开发进程退出会停止本次启动的全部进程；已占用端口会在启动前报错，请先停止之前手动启动的实例。

开发 workspace 的 `sparq.dev.yaml` 使用`config/sparq.workspace.watch.yaml`，同时监听默认壳及 `sparq`、`sparq-schema`、`sparq-kernel`、`sparq-protocol`、`sparq-blade` 源码，变更后重新构建 `tmp/sparq-dev`；Shell 使用 Vite HMR。更换监听配置后需停止原联调进程再执行 `make dev-app`，否则旧进程仍使用原监听范围。

独立克隆时将 `backend.watch_file` 改为 `config/sparq.watch.yaml`，该配置只监听当前应用，不要求相邻框架仓库。

已安装新版工具后，可以将上面的 `go run ./sparq-tool/cmd/sparq-tool` 替换为 `sparq-tool`。旧版工具不识别新增 `admin` 字段，请先使用源码入口。只需启动后端时仍可在 `sparq-app/` 执行 `make dev`。正式构建路径继续使用 `build.yaml` 的 `admin.path`、`frontend.path`，与开发进程配置独立。

## 构建

正式应用构建使用配置文件，不再从 `sparq-app`、`sparq-frontend` 或 Website 目录之间推导组件。可复制 [build.example.yaml](build.example.yaml) 为 `build.yaml` 后按项目路径修改：

```bash
sparq-tool build app --config sparq-app/build.yaml --target linux/amd64
sparq-tool build app --config sparq-app/build.yaml --env release --version 0.2.0
```

`app.path`、`app.package` 和 `app.binary` 描述应用入口；`updater.path`、`admin.path`、`frontend.path` 只有设置后才参与构建。前端项目会执行 `commands` 中的 package script（默认 `build`），并要求生成非空 `dist/`。需要发布应用运行文件或目录时，在 `copy` 中显式声明，源路径相对于 `app.path`，目标路径相对于 `output.dir`；未声明的配置文件不会自动发布。构建结果统一写入 `output.dir`：Admin 位于 `public/admin/`，二次开发前端位于 `public/admin/__app__/`，版本和 Git Hash 位于 `build-manifest.json`。

`--env release` 会读取与基础配置同目录的 `build.release.yaml`，不会读取 `config/app.dev.yaml` 或改变运行时 `--env` 参数。前端包管理器由 `sparq-tool` 自动识别，不需要在构建配置中声明 `pnpm`。

macOS/Linux：

```bash
make dev
make build
make build GOOS=linux GOARCH=amd64
make release VERSION=0.1.0
```

`release` 会将 `VERSION` 自动注入 CLI 版本（例如 `v0.1.0`）。如需追加其他 Go linker flags，可通过 `LDFLAGS` 传入。

统一使用 `production` 构建标签选择生产能力集合。默认壳正式发布同时包含 MySQL 和 PostgreSQL，不包含 SQLite：

```bash
make release VERSION=0.2.0
# 直接构建生产二进制
make build TAGS=production
```

`make build`、`go build` 和 `go test` 不加标签时保留 SQLite、MySQL、PostgreSQL 三个驱动，便于本地开发和测试。`release` 与 `release-optimized` 默认使用 `RELEASE_TAGS=production`。

`production` 是跨模块的生产构建约定，后续确有开发专用能力时沿用该标签；它与运行配置 `app.env`、版本号和调试符号开关独立。旧的数据库专用构建标签已移除。

插件构建默认使用 `go.tags: production`，测试阶段默认不加标签；本地调试 Runner 可显式设置 `go.tags: ""`。自定义标签会替换默认值，生产扩展标签应写为 `production,custom`。

生产安装时选择 MySQL 或 PostgreSQL，安装器只展示当前二进制已注册的驱动。基础 SQLite 连接仅在被默认连接或连接组引用时启用，安装配置切换到其他数据库后不会额外打开 SQLite。已有 SQLite 安装需要先迁移到 MySQL/PostgreSQL，或继续使用无标签的开发构建；仅修改 `app.env` 不会加入驱动。配置引用未编入的驱动时，启动会返回 `not included in this build` 错误。

正式分发时可以使用精简构建，默认关闭 CGO 并通过 `-s -w -buildid=` 去除符号表、DWARF 调试信息和构建 ID：

```bash
make release-optimized VERSION=0.2.0
```

生产安装包使用 `sparq-tool` 分两步生成。`build app` 按工作区 `build.yaml` 构建配置声明组件，`package app` 再按目标平台组装配置与公开资源：

```bash
sparq-tool build app .. --target linux/amd64 --version 0.2.0
sparq-tool package app .. --target linux/amd64 --version 0.2.0
```

默认构建会移除 Go 调试信息；需要使用 Delve 或检查 Admin source map 时，显式传入 `build app --debug`。前端路径和构建脚本统一在 `build.yaml` 中声明。

`sparq-app` 只包含默认壳和运行时目录。应用、updater、Admin 和二次开发前端均通过构建配置按需启用，分别写入输出目录的根路径、`public/admin` 和 `public/admin/__app__`；Website 使用自己的 `build.yaml`，不会被默认壳归档带入。

Windows：

```powershell
.\make.cmd dev
.\make.cmd build
.\make.cmd build -GOOS linux -GOARCH amd64
.\make.cmd release -Version 0.1.0
```

默认多平台发布目标：

```text
linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64
```

## 配置

默认配置文件：

```text
sparq-app/config/app.yaml
```

完整配置示例：

```text
sparq-app/config/app.example.yaml
```

开发环境会继续加载：

```text
sparq-app/config/app.dev.yaml
```

CLI 参数可以覆盖默认路径和常用配置：

```bash
./bin/sparq --root . --config ./custom/app.yaml --addr :19090 --env dev
```

## 运行数据

默认运行数据写入：

```text
sparq-app/storage/
```

`run/` 与 `storage/` 属于默认壳实例，不属于 `github.com/zane-xin/sparq` 核心包。`sparq-tool package app` 生成的首次安装包包含 `config/app.yaml`、`config/app.example.yaml` 和已经构建的 `public/`，但会排除实例配置 `config/app.install.yaml` 和运行期插件资源 `public/admin/plugin-assets/`；`run/`、数据库、日志、插件包和更新临时目录由 Web 安装器或宿主首次运行时创建。

## 本地插件聚合

本地插件根 package 公开 `PluginCode`、`Manifest()` 和 `Register(ctx, runtime)`。默认壳通过工具生成 `plugin.PluginPackage` 装配文件，不需要维护第二套插件列表或编写 Local 适配层：

```bash
go run ./sparq-tool/cmd/sparq-tool localplugins generate .
```

生成器扫描 `plugins/*/plugin.yaml` 和 `go.mod`，把声明支持 `local` 的插件写入 `cmd/sparq/plugins_gen.go`。生成文件显式引用插件根 package 的 `Manifest()` 和 `Register`，并通过 `sparq.WithPluginPackages` 把 Package 传给当前 App。App 在启动时将 Bundled、Local 和已安装 Remote Package 合并成私有 Catalog；PluginHost 为进程内组件创建可信 Identity 和 Registration Draft，原子提交到当前 App 的唯一 PluginRegistry，并接管 `plugin.Instance` 的启动和逆序停止。宿主不会在运行期读取 workspace 中的 `plugin.yaml`。

Local 插件共享宿主进程的数据库、Redis、Cache 和 Logger；插件间仍通过 capability 调用，不直接引用对方 Service。插件根 `Register` 只进入内部模块装配，数据库迁移、Provider、路由和实例创建由插件 `internal` 模块处理。

官方插件当前没有公开发布版本，源码模块由根目录 `go.work` 管理。本地聚合构建必须从该 workspace 执行，不能在 `sparq-app/go.mod` 中添加指向公共代理的伪版本依赖。

## 使用固定版本的 Admin 归档独立发布

先发布 Go 依赖并更新本仓库 go.mod/go.sum；`make check-release` 始终关闭外层 Go workspace。下载可信的 Admin 归档及摘要后，在本仓库执行（下列版本与路径需替换为实际发行值）：

```sh
make release VERSION=0.3.0 \
    ADMIN_VERSION=0.2.0 \
    ADMIN_ARTIFACT=/absolute/path/sparq-admin-0.2.0.tar.gz \
    ADMIN_SHA256=<归档对应的64位SHA256>
```

App 版本与 Admin 版本独立。脚本先校验归档摘要、Admin 版本、文件清单和内容指纹，然后解压到新发布目录。拒绝路径越界、符号链接、内部插件资源和已有目标；不会覆盖运行中的 `__app__` 或 `plugin-assets`。发行包包含默认配置、Runtime 二进制、指定 Admin 和 release.json，归档及 SHA256 位于 dist/。

本地 public/admin、public/assets、上传目录、storage 和安装配置不会复制进默认发行物。业务应用的额外静态资产应使用自己的显式构建配置。根 workspace 的 build.dev.yaml 仅用于联调，不是正式发布输入。既有工具的官方签名整包通道继续遵循其原有版本约束。

验证归档处理：`python3 -m unittest discover -s scripts -p 'test_*.py'`。
