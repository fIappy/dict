# Web 端部署指南

本项目的 Web 端由**两个容器**组成：一个纯静态的 Flutter Web 前端，以及一个提供本地词典能力的 Dart 后端。
浏览器沙箱无法读取本机文件，因此 `.mdx` / `.mdd` 的解析、检索与发音资源读取全部由后端完成，前端通过 HTTP API 调用。

---

## 0. 本次实测记录（WSL2 Ubuntu + Docker 28.0.4）

在 WSL2 中执行 `docker compose -f docker/docker-compose.yml up -d --build` 后的实测结果：

| 项目 | 结果 |
|---|---|
| 镜像构建 | `local-dict-backend` / `local-dict-web` 均成功 |
| 容器状态 | backend `healthy`，web `Up` |
| `GET /api/health` | `{"status":"ok","dictionaries":1,"enabled":1,"totalEntries":434589,...}` |
| `GET /api/dictionaries` | 返回 1 本词典，含 `.mdx` / `.mdd` / `.css` 路径与 434,589 词条数 |
| `GET /api/search?q=tele&limit=5` | `exact` → `prefix` 分级返回，服务端耗时 **6 ms** |
| `GET /api/lookup?word=hello` | 完整词条：`American / Etymology / Explanation / Examples` 四个标签页、音标、例句 |
| `GET /api/audio?key=hello.mp3` | `200`，浏览器播放实测取回 17,756 字节（**27 ms**） |
| Range 请求 | `206 Partial Content` + `content-range: bytes 0-1023/17756` |
| 前端静态资源 | `main.dart.js` 3,580,791 B、`canvaskit.wasm` 7,229,946 B、音标 mp3 字节数与源文件一致 |
| MIME / 压缩 | `application/wasm`、`application/javascript`、`audio/mpeg`、`application/json` 均正确；gzip 生效 |
| 浏览器端到端 | 检索 → 查词 → 发音全链路通过，**控制台 0 错误、0 失败请求** |
| 词典页状态 | 「已连接后端词典服务 / 词典由后端提供（1 本，共 434589 条词条）」+「含配套音频库 (.mdd)」「含专用样式表 (.css)」|

---

## 1. 架构总览

```mermaid
graph LR
    B["浏览器 / Flutter Web 前端<br/>:8088"]
    S["词典后端 (Dart AOT)<br/>:8080"]
    D["词典目录 (只读挂载)<br/>*.mdx + *.mdd"]

    B -- "GET /api/search" --> S
    B -- "GET /api/lookup" --> S
    B -- "GET /api/audio" --> S
    S -- "RandomAccessFile" --> D
```

| 能力 | 执行位置 | 说明 |
|---|---|---|
| 词典检索 / 词条查询 | **后端** | `.mdx` 随机访问解析，434,589 条词条索引常驻内存 |
| 词典原声发音 | **后端** | 从 `.mdd` 按需抽取 MP3 字节流，支持 HTTP Range |
| 音标（IPA）学习 | 前端（离线） | 打包在 `assets/audio/ipa/` |
| 26 字母发音 | 前端（离线） | 打包在 `assets/audio/letters/` |
| 词频排行榜 | 前端（离线） | 打包在 `assets/data/frequency_5000.json` |
| 生词本 / 查词历史 | 前端（离线） | 浏览器 localStorage |

后端与桌面端/安卓端**复用同一套解析器**（`lib/core/mdx/*`），不存在第二份实现。

---

## 2. 前置条件

- Docker 24+ 与 Docker Compose v2
- 约 6 GB 可用磁盘（Flutter 构建镜像较大）
- 词典文件（`.mdx` 必需，同名 `.mdd` 可选，用于发音）

> **Windows 用户**：以下命令在 **WSL2 (Ubuntu)** 中执行。若 Docker Desktop 已开启 WSL 集成，
> WSL 内可直接使用 `docker` 命令。

---

## 3. 快速开始（Docker Compose）

```bash
cd /mnt/d/proj/flutter/dict        # 仓库根目录

docker compose -f docker/docker-compose.yml up -d --build
```

首次构建需要拉取 Flutter 镜像并编译 Web 产物，耗时较长；之后为增量构建。

启动后：

| 服务 | 地址 |
|---|---|
| Web 前端 | http://localhost:8088 |
| 后端 API | http://localhost:8080 |

验证：

```bash
curl -s http://localhost:8080/api/health
# {"status":"ok","dictionaries":1,"enabled":1,"totalEntries":434589,"uptimeSeconds":3}

curl -s "http://localhost:8080/api/lookup?word=hello" | head -c 300
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' \
  "http://localhost:8080/api/audio?key=hello.mp3"
# 200 17756
```

浏览器打开 http://localhost:8088 ，左侧「词典」页应显示**已连接后端词典服务**。

停止 / 清理：

```bash
docker compose -f docker/docker-compose.yml down          # 停止
docker compose -f docker/docker-compose.yml down --rmi local   # 同时删除镜像
```

### 词典路径不是默认值时

默认挂载仓库内的 `Dictionary.com 20260913_hahaya/`。指向其它目录：

```bash
DICT_PATH=/mnt/d/dicts docker compose -f docker/docker-compose.yml up -d --build
```

Compose 中的相对路径以 `docker/` 目录为基准，因此默认值 `../Dictionary.com 20260913_hahaya`
即仓库根目录下的词典文件夹。

---

## 4. 单独构建 / 运行

### 4.1 仅后端

```bash
docker build -f docker/Dockerfile.backend -t local-dict-backend .
docker run --rm -p 8080:8080 \
  -v "/mnt/d/proj/flutter/dict/Dictionary.com 20260913_hahaya:/dictionaries:ro" \
  local-dict-backend
```

### 4.2 仅前端（指向已有后端）

```bash
docker build -f docker/Dockerfile.web \
  --build-arg DICT_API_BASE=http://192.168.1.10:8080 \
  -t local-dict-web .
docker run --rm -p 8088:80 local-dict-web
```

---

## 5. 配置项

### 5.1 后端

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DICT_DIR` | `/dictionaries` | 词典目录，**递归**扫描其中的 `.mdx`；多个目录用 `;` 分隔 |
| `DICT_HOST` | `0.0.0.0`（镜像内） | 监听地址 |
| `DICT_PORT` | `8080` | 监听端口 |

也支持命令行参数：`--dir <目录> --host <地址> --port <端口>`。

词典与音频文件的配对规则：同目录下**同名**的 `.mdx` 与 `.mdd` 自动关联
（例如 `Dictionary.com 20260913.mdx` + `Dictionary.com 20260913.mdd`）。
同目录下任意 `.css` 会被记录为词条样式表。

### 5.2 前端

后端地址按以下**优先级**解析：

1. URL 查询参数 `?api=http://host:port`（会写入浏览器 localStorage，后续自动生效）
   ```
   http://localhost:8088/?api=http://192.168.1.10:8080
   ```
2. 浏览器已保存的设置
3. **编译期** `--dart-define=DICT_API_BASE=...`（Docker 通过 `--build-arg DICT_API_BASE=` 传入）
4. 网页自身 Origin（同源部署时自动生效）
5. `http://127.0.0.1:8080`

因此：**跨源部署**（前端与后端不同端口）用第 3 步写死地址；
**同源部署**（nginx 反向代理 `/api/`）把 `DICT_API_BASE` 置空即可零配置运行。

---

## 6. API 契约

所有响应为 `application/json; charset=utf-8`（音频除外）。跨源请求返回
`Access-Control-Allow-Origin: *`。

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/api/health` | 健康检查：词典数量、总词条数、运行秒数 |
| `GET` | `/api/dictionaries` | 已加载词典列表（含启用状态、词条数、文件路径） |
| `POST` | `/api/dictionaries/<id>/enabled` | 启用/停用某本词典，body：`{"enabled": true}` |
| `GET` | `/api/search?q=&limit=` | 检索，返回 `exact` → `prefix` → `substring` 分级的词列表 |
| `GET` | `/api/lookup?word=` | 查词，返回完整解析词条（标签页、正文面板、音标、例句） |
| `GET` | `/api/audio?key=` | 发音 MP3 字节流，支持 `Range`（206 Partial Content） |

示例：

```bash
# 前缀检索
curl -s "http://localhost:8080/api/search?q=tele&limit=5"
# {"query":"tele","results":[
#   {"word":"tele","matchType":"prefix","dictionaryId":"dictionary-com-20260913","dictionaryName":"Dictionary.com"},
#   ... ]}

# 查词
curl -s "http://localhost:8080/api/lookup?word=hello" | jq '.entry | {word, phonetic, soundKey, tabs: [.tabs[].label]}'
# { "word":"hello", "phonetic":"[he-loh...]", "soundKey":"hello.mp3",
#   "tabs":["American","Etymology","Explanation","Examples"] }

# 发音（含 Range 请求）
curl -s -D- -o /dev/null -H 'Range: bytes=0-1023' \
  "http://localhost:8080/api/audio?key=hello.mp3" | grep -i content-range
# content-range: bytes 0-1023/17756
```

> `/api/search` 只返回词形与词典归属；中文简释、CEFR 等级、考纲标签由**前端**用本地词频库
> 富化，因此后端不重复实现该逻辑。

---

## 7. 生产部署：单域名 + TLS（推荐）

把前端与后端收敛到同一个 Origin，可免除跨源配置，并便于套用 HTTPS。

前端镜像用**空** `DICT_API_BASE` 构建，从而回退到网页 Origin：

```bash
docker build -f docker/Dockerfile.web --build-arg DICT_API_BASE= -t local-dict-web .
```

在 nginx（或任何反向代理）中把 `/api/` 转发到后端：

```nginx
location /api/ {
    proxy_pass http://backend:8080;      # 结尾无斜杠 => 保留完整路径
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header Range $http_range;  # 音频断点续传必需
    proxy_set_header If-Range $http_if_range;
    proxy_buffering off;                 # 音频流不落盘缓冲
    proxy_read_timeout 60s;
}
```

> 若 `backend` 主机名可能不存在（例如仅部署前端），请改用变量形式延迟解析，
> 否则 nginx 会在**启动时**因解析失败而退出：
> ```nginx
> resolver 127.0.0.11 ipv6=off valid=10s;   # Docker 内置 DNS
> set $upstream backend;
> proxy_pass http://$upstream:8080;
> ```

---

## 8. 不使用 Docker 的部署

### 8.1 后端

```bash
flutter pub get
dart compile exe server/dict_server.dart -o dict_server     # 可选：编译为原生可执行文件
dart run server/dict_server.dart --dir "/path/to/dicts" --port 8080
```

开发期直接 `dart run` 即可；生产建议 `dart compile exe`，产物无 Dart 运行时依赖。

### 8.2 前端静态托管

```bash
flutter build web --release --dart-define=DICT_API_BASE=http://your-backend:8080
# 产物位于 build/web/，可直接托管于任意静态服务器 / 对象存储 / CDN
```

托管到纯静态环境时，注意 `/api` 不可用会导致词典功能不可用，但音标、字母、词频三大模块仍可离线使用。

---

## 9. 故障排查

| 现象 | 原因与处理 |
|---|---|
| 词典页显示「未连接后端词典服务」 | 后端未启动或地址不对。`curl http://localhost:8080/api/health` 验证；或用 `?api=` 指定地址后刷新 |
| 页面能开但检索无结果 | `docker compose logs backend` 查看是否 `no .mdx archive found`；确认 `DICT_PATH` 挂载正确 |
| 发音无声 | 后端日志中 `/api/audio` 返回 404 表示该词无 `.mdd` 音频，前端会自动回退到在线音源 |
| `docker build` 卡在拉取镜像 | 首次需拉取 Flutter 镜像（数 GB），耐心等待或配置镜像加速 |
| 修改代码后页面未更新 | Flutter 会注册 Service Worker 缓存。强制刷新（Ctrl+Shift+R），镜像中的 `index.html` 与 `flutter_service_worker.js` 已设置 `no-store` |
| 构建期出现 `nuget.exe not found` | 与本 Web 构建无关，仅当为本机编译 Windows 桌面端且启用了需 NuGet 的插件时出现 |
| 构建期 `version solving failed ... requires SDK version` | 镜像内 Flutter/Dart 低于 `pubspec.yaml` 的 `environment.sdk` 下限。本项目的下限已按真实需求设为 `>=3.8.0 <4.0.0`（依赖 Dart 3.8 的 null-aware elements 与 Flutter 3.32 的 `RadioGroup` / `CardThemeData`）；若更换更旧的镜像仍会失败，请换用更新的 Flutter 镜像 |
| 构建期 `PathNotFoundException: Cannot open file, path = '/out/dict_server'` | AOT 输出目录不存在。Dockerfile 已用 `mkdir -p /out` 先行创建 |
| nginx 返回错误的 Content-Type（如 JS 变成 `text/plain`） | nginx 的 `types` 块是**替换**而非追加继承的 MIME 表。本仓库仅在匹配单一扩展名的 `location` 内声明额外类型；若自行添加，切勿在 `server`/`http` 层整体重写 `types` |

查看日志：

```bash
docker compose -f docker/docker-compose.yml logs -f backend
docker compose -f docker/docker-compose.yml logs -f web
```

---

## 10. 安全说明

- 后端**没有鉴权**，且 `/api/dictionaries` 会返回词典文件的绝对路径。
  请仅在**受信任的内网或本机**使用；如需暴露到公网，务必在前置代理上加认证与访问控制。
- `DICT_DIR` 以只读方式挂载（Compose 中 `:ro`），后端只读取词典文件，不写入任何内容。
- 跨源策略为 `Access-Control-Allow-Origin: *`，便于本地多端口调试；公网部署请收紧为具体来源。
- 词典文件受其自身授权约束，本项目不分发词典内容。

---

## 11. 构建产物对照

| 平台 | 构建命令 | 产物 |
|---|---|---|
| Windows 桌面端 | `flutter build windows --release` | `build/windows/x64/runner/Release/`（需整体分发） |
| Android | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Web | `flutter build web --release` | `build/web/` |
| 后端 | `dart compile exe server/dict_server.dart` | `dict_server`（单文件，无运行时依赖） |
| Web + 后端 | `docker compose -f docker/docker-compose.yml up -d --build` | `local-dict-web` / `local-dict-backend` 镜像 |
