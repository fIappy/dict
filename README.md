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
- **音标（IPA）** — 48 条音标数据，与[剑桥音标表](https://dictionary.cambridge.org/help/phonetics.html)
  逐行对应（含 `/ɒ/ /ɜː/ /əʊ/` 等英音专有、`/ɝː/ /ɚ/ /oʊ/ /t̬/` 等美音专有）：发音要领、口型舌位、
  拼写规律、例词试听，以及与其它音标的组合发音（声母拼读、辅音连缀、尾音闭合、不送气浊化）。
  示范音是剑桥自己的原声、UK/US 分轨；单元音按「长元音 + 对应短元音」成对同排展示。
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
| Web | ✅ | **Dart 后端 HTTP API** | 单个入口（nginx 静态资源 + `/api/` 代理） |

### Web 端架构

浏览器沙箱无法读取本机 `.mdx` / `.mdd`，因此配套一个 **Dart 后端**
（`server/dict_server.dart`，`shelf` + `dart compile exe`）提供检索、查词与发音 API。
后端与桌面端/安卓端**复用同一套解析器**（`lib/core/mdx/*`），不存在第二份实现。

部署上前后端**整合为单一入口**：只暴露一个端口，nginx 托管静态前端并把 `/api/` 反向代理到后端容器，
因此前后端同源——不需要 CORS，后端也不会把词典文件路径暴露到网络上。

```
浏览器 ──▶ web 容器 (nginx, :8088) ──▶ backend 容器 (Dart, 仅内网)
                    │ 静态资源                │ .mdx / .mdd 只读挂载
                    └ /api/* ────────────────┘
```

音标、字母、词频三个模块在前端完全离线可用，不依赖后端。

## 快速开始

### Web 端（Docker）

```bash
docker compose -f docker/docker-compose.yml up -d --build
# 打开唯一入口 http://localhost:8088 （前端与 API 同源）
```

详见 **[docs/WEB_DEPLOYMENT.md](docs/WEB_DEPLOYMENT.md)**（含 API 契约、HTTPS、分离部署、故障排查）。

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

### `.mdd` 与发音（重要）

`.mdx` 只含词条正文，**发音原声在 `.mdd` 里**。两者必须**文件主名相同**才会配对：

```
Dictionary.com 20260913.mdx   ← 正文（必需）
Dictionary.com 20260913.mdd   ← 发音原声（可选，约 1.5 GB）
```

配对结果会显示在「词典」页的卡片上：`含配套音频库 (.mdd)` 或 `无独立音频库`。

| 场景 | 行为 |
|---|---|
| 有 `.mdd` | 播放词典自带原声，离线可用 |
| 没有 `.mdd` | 回退到在线词典音源（需联网）；Windows 离线时回退系统语音，Android 离线时无声 |

**各端导入方式**

- **Windows**：把 `.mdx` 与同名 `.mdd` 放在同一目录，导入 `.mdx` 即可自动配对；
  导入后再补 `.mdd` 也可——重新启动应用时会自动重新探测。
- **Android**：系统文件选择器（SAF）会把选中的文件**复制到应用缓存目录的独立子目录**，
  因此同目录下的 `.mdd` 永远无法被自动发现。**必须在同一次选择中同时选中 `.mdx` 和 `.mdd`**，
  应用会把两者复制到应用私有目录并按主名配对（缓存目录可能被系统回收，不宜直接引用）。
  只选 `.mdd` 会被拒绝并提示需要同时选中 `.mdx`。

**Docker 部署时**词典不打进镜像，而是在运行时只读挂载给后端容器；
新增词典无需重建镜像，`POST /api/reload` 可热加载（免重启）。
详见 [Web 部署指南 §3.1 词典配置](docs/WEB_DEPLOYMENT.md#31-词典配置部署后如何加词典)。

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
│   ├── ipa/          # 48 条音标数据（剑桥音标表口径）
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
├── audio/ipa/        # 86 个音标示范音（剑桥原声，UK/US 分轨，见「音标音频的来源」）
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
flutter test             # 单元与 Widget 测试（13 项）
dart analyze server      # 后端静态分析
```

### Windows 打包

`flutter build windows --release` 要求两样本机可能没有的东西，缺一个就直接退出（与代码无关）：

| 报错 | 原因 | 处理 |
|---|---|---|
| `Building with plugins requires symlink support` | 未开开发者模式且当前不是管理员终端，Flutter 无法给 5 个 Windows 插件建符号链接 | 用 junction 顶替：`cmd /c mklink /J windows\flutter\ephemeral\.plugin_symlinks\<插件> <pub-cache 路径>`（清单见 `.flutter-plugins-dependencies` 的 `windows` 段）。已存在的链接会被跳过，因此不需要开发者模式 |
| `Unable to find suitable Visual Studio toolchain` | VS 2022 缺 `Microsoft.VisualStudio.Component.VC.CMake.Project`（C++ CMake 工具） | VS Installer 补装该组件；或按下面绕过 Flutter 直接构建 |

绕过方式（本机可用：pip 装的独立 CMake + 已配置过的 `build/windows/x64`）：

```bash
cmake --build build/windows/x64 --config Release --target INSTALL
```

CMake 的 `flutter_assemble` 目标仍会调用 Flutter 工具，所以 `data/app.so`（AOT）与
`data/flutter_assets` 都会重新生成，产物落到 `build/windows/x64/runner/Release/`。

**构建前先关掉正在运行的 `local_dict.exe`**：引擎映射着 `data/flutter_assets/fonts/*.otf`，
覆盖被映射的文件时 INSTALL 会报 `Invalid argument`。（Android 打包需要完整的 Android SDK + JDK，
只有 platform-tools 时 `flutter doctor` 会报 `[X] Android toolchain`，无法出 APK。）

### 音标音频的来源

`assets/audio/ipa/<key>_uk.mp3` 与 `<key>_us.mp3` **就是剑桥词典自己播放的那几条示范音**：
[剑桥音标表](https://dictionary.cambridge.org/help/phonetics.html) 每行喇叭对应的
`{uk,us}_phonetics_sound_<例词>_2023feb.mp3`。音标卡片的「音标纯音示范」按钮播的就是它，
与你在那页上点喇叭听到的逐条一致：

```bash
python tool/fetch_cambridge_ipa_audio.py --check          # 只对照 ipa_data.dart 报告缺口
python tool/fetch_cambridge_ipa_audio.py                  # 抓全量（48 音标 / 86 条）
python tool/fetch_cambridge_ipa_audio.py --force --prune   # 重抓，并删掉多余文件
```

脚本直接读 `lib/core/ipa/ipa_data.dart`：每个音素用它那一行的 `cambridgeExampleWord`
换算出 URL，所以「数据里加了音标却没抓音频」会被 `--check` 直接报出来。三条约束是硬性的：

- 只接受 `_phonetics_sound_`（孤立音素），永不取 `_phonetics_word_`（整词录音）；
- 只写剑桥真的提供的口音——`/ɒ/ /ɜː/ /əʊ/ /ɪə/ /eə/ /ʊə/` 只有英音，`/ɝː/ /ɚ/ /oʊ/ /t̬/` 只有美音；
- 数据里出现剑桥音标表没有的符号（`/tr/ /dr/ /ts/ /dz/` 已按此移除）时直接失败，不伪造音频。

UK-only 行的美音按钮播放对应音标（`/ɒ/`→`/ɑː/`、`/ɜː/`→`/ɝː/`、`/əʊ/`→`/oʊ/`）的录音；
`/ɪə/ /eə/ /ʊə/` 在剑桥表里没有美音对应行，按钮置灰，而不是"点了没声音"。

字典站点在 Cloudflare 后面，直连、curl、无头 Chromium 一律 403，脚本因此从 Wayback Machine
的同一条 URL 取原始字节（体积一致，再校验 ID3 / MPEG 帧同步），第二来源是公共 CORS 代理。

**离线回退**（拿不到网络时才用）：两个生成器都产出不带口音后缀的 `<key>.mp3`。
播放统一走 `lib/core/audio/ipa_asset.dart` 的 `resolveIpaAsset()`，按
`<key>_<accent>` → 另一个口音 → `<key>` 取第一个存在的资源（查 AssetManifest，
原生与 Web 行为一致）；三者都不存在时静默返回、不播错口音：

| 工具 | 音源 | 代价 |
|---|---|---|
| `tool/generate_ipa_audio_from_mdd.dart` | 词典自带 `.mdd` 真人录音，按例词切一段 | 需要那 1.7 GB 的 `.mdd`；只有美音一条轨 |
| `tool/generate_ipa_audio.py` | espeak-ng 现场合成 | 共振峰合成器，电子音 |

```bash
dart run tool/generate_ipa_audio_from_mdd.dart --check   # 只出报告，不写文件
dart run tool/generate_ipa_audio_from_mdd.dart           # 需要 ffmpeg
python tool/generate_ipa_audio.py --check                # 只校验音素映射
python tool/generate_ipa_audio.py                        # 需要 espeak-ng + ffmpeg
```

`.mdd` 生成器复用 `lib/core/mdx/mdd_reader_native.dart`（MDict 容器全项目只有一份解析实现），
按 `vowel`（词中能量最高段）/`onset`（词首 160 ms）/`coda`（词尾 160 ms）/`word` 四种模式取段；
像 `cats` 这种词内本就有两次能量隆起（元音、`/ts/` 摩擦）的会按 ≥350 ms 静音间隔判为一遍。
剪完做 RMS 归一化（−20 dBFS，峰值上限 −1 dBFS，首尾 5 ms 淡入淡出）再编码成 64 kbps 单声道 mp3，
并**与源录音做滑动互相关**（48 条全部在预期偏移处 Pearson ≥ 0.917），而不是"听着像"。

> 别用单词读音冒充音素示范。`/ts/` 播 "cats"、`/dr/` 播 "dream"、`/ɚ/` 播 "water"
> 这类"念例词"的做法，时长会从 0.16 s 涨到 0.4 s 以上，听起来像读对了，实际是把整词塞进音标栏。
> 要用 TTS 就必须走音素输入（espeak-ng 的 `[[...]]`）；词级 TTS（Edge/Azure 的明文接口）
> 给不了孤立音素，摩擦音、破擦音尤其无解。
>
> 也别用按文件名从第三方仓库挑的录音：那类多是**基本元音（cardinal vowel）**，cardinal [ʌ]
> 是后半开元音，英语 /ʌ/（cup）是央化的 [ɐ]；cardinal [e] 是次闭前元音，英语 /e/（bed）实际是 [ɛ]。

## 文档

- [Web 端部署指南](docs/WEB_DEPLOYMENT.md) — Docker、单源 + TLS、静态托管、API 契约、故障排查
- [后端源码](server/dict_server.dart) — 接口实现
