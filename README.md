# 本地词典 · Local Dictionary

基于 Flutter 的本地 MDict 词典应用，支持 Windows 桌面端、Android 端与 Web 端。
一个代码库，三端运行；Web 端通过自带的 Dart 后端获得本地词典能力。

## 功能

- **词典查询** — 直接解析 MDict `.mdx` / `.mdd` 归档，本机 434,589 词条索引
  加载约 66 ms，单词检索 1–2 ms。
- **部分匹配检索** — 精确 → 前缀 → 包含三级排序，输入即搜。
- **多词典** — 同时加载多本词典联合查词，可逐本启用/停用。
- **发音** — 优先播放 `.mdd` 内的高保真原声；缺失时回退系统语音/在线音源。
  美音、英音双轨；`lead` / `read` 等同形异音词的多个读音分别提供。
- **音标（IPA）** — 48 个英式音标全量数据：发音要领、口型舌位、拼写规律、
  例词试听，以及与其它音标的组合发音（声母拼读、辅音连缀、尾音闭合、不送气浊化）。
  单元音按「长元音 + 对应短元音」成对同排展示。
- **字母** — 26 个字母的标准发音（美/英双音，如 `Z` 的 `zee` / `zed`）与自然拼读规律。
- **词频** — Top 20,000 词频榜单，支持自定义区间（如 `5000-6000`）、分页与跳页；
  区间设置持久化，重启后自动恢复。
- **生词本** — 分组收藏、助记笔记、分组颜色标签，本地持久化。
- **词条正文** — 多标签页（American / Etymology / Explanation / Examples）、
  全文可选可复制、正文与小喇叭链接联动发音。
- **UI** — 桌面端三栏工作台（可拖拽分隔条），移动端底部导航，Material 3 明暗主题。

## 平台支持

| 平台 | 状态 | 词典能力来源 | 产物 |
|---|---|---|---|
| Windows 桌面端 | ✅ | 本地文件系统 | `build/windows/x64/runner/Release/` |
| Android | ✅ | 本地文件系统 | `build/app/outputs/flutter-apk/app-release.apk` |
| Web | ✅ | **Dart 后端 HTTP API** | `build/web/` + `server/dict_server.dart` |

Web 端受浏览器沙箱限制无法读取本机 `.mdx`/`.mdd`，因此配套一个 Dart 后端
（`server/dict_server.dart`）提供检索、查词与发音 API，并与桌面端**复用同一套解析器**。
音标、字母、词频三个模块在前端完全离线可用。

## 快速开始

### Web 端（Docker）

```bash
docker compose -f docker/docker-compose.yml up -d --build
# 前端 http://localhost:8088  ·  后端 http://localhost:8080
```

详见 **[docs/WEB_DEPLOYMENT.md](docs/WEB_DEPLOYMENT.md)**。

### 桌面端 / Android

```bash
flutter pub get
flutter build windows --release     # 或 flutter build apk --release
```

### 后端单独运行

```bash
dart run server/dict_server.dart --dir "/path/to/dicts" --port 8080
```

## 词典文件

词典文件（约 1.7 GB）**不纳入版本控制**，需自行准备并放到仓库根目录：

```
Dictionary.com 20260913_hahaya/
├── Dictionary.com 20260913.mdx      # 词条正文（必需）
├── Dictionary.com 20260913.mdd      # 发音音频（可选）
└── dcom-mdx-style.css               # 词条样式（可选）
```

应用首次启动会自动探测该目录。也可在「词典」页手动导入任意 `.mdx`。
命令行指定其它目录：`DICT_DIR=/path/to/dicts`（后端）或 `--dir` 参数。

## 项目结构

```
lib/
├── core/
│   ├── mdx/          # MDict 解析器（mdx_reader · mdd_reader · mdx_entry）
│   │                 # 通过条件导出在原生/Web 间分派
│   ├── api/          # 后端 API 客户端与地址解析
│   ├── database/     # sqflite（原生）/ localStorage（Web）双实现
│   ├── services/     # 词典服务（原生文件系统 / Web HTTP）
│   ├── audio/        # 音频播放（原生 mdd+系统语音 / Web 后端+在线）
│   ├── ipa/          # 48 音标数据
│   ├── alphabet/     # 26 字母数据
│   └── frequency/    # 词频库
├── providers/        # 状态管理（provider）
└── ui/               # 界面：screens / widgets / theme
server/
└── dict_server.dart  # 本地词典 HTTP 后端
docker/
├── Dockerfile.backend
├── Dockerfile.web
├── nginx.conf
└── docker-compose.yml
assets/
├── audio/ipa/        # 48 个音标原声
├── audio/letters/    # 26 字母 × 美/英音
└── data/             # Top 20,000 词频表
```

### 跨平台实现方式

原生与 Web 的差异通过**条件导出**隔离，业务代码不感知平台：

```dart
// lib/core/mdx/mdx_reader.dart
export 'mdx_reader_web.dart' if (dart.library.io) 'mdx_reader_native.dart';
```

`dart:io` / `sqflite` / `path_provider` 仅出现在 `*_native.dart` 中，Web 端永不编译到。

## 开发

```bash
flutter analyze          # 静态分析（0 issues）
flutter test             # 单元与 Widget 测试（9 项）
dart analyze server      # 后端静态分析
```

## 文档

- [Web 端部署指南](docs/WEB_DEPLOYMENT.md) — Docker、单源 + TLS、静态托管、API 契约、故障排查
- [后端源码](server/dict_server.dart) — 接口实现
