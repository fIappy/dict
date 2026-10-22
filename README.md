# 本地词典 · Local Dictionary

基于 Flutter 的本地 MDict 词典应用，支持 Windows 桌面端、Android 端与 Web 端。
一个代码库，三端运行；Web 端通过自带的 Dart 后端获得本地词典能力。

## 功能

- **词典查询** — 直接解析 MDict `.mdx` / `.mdd` 归档，本机 434,589 词条索引
  加载约 66 ms，单词检索 1–2 ms。
- **多记录词条** — 一个词头拆成多条记录的词典（如 SIO 双向双解：发音条、简明释义、
  词语搭配、权威例句各一条记录）会按归档顺序合并成一条正文，`@@@LINK` 跳转也展开到目标词条的全部记录。
- **部分匹配检索** — 精确 → 前缀 → 包含三级排序，输入即搜。
- **词条内短语/例句发音** - 词条详情里的「词语搭配」与「权威例句」逐行带 🔊，
  也可以一键「顺序播放 N 句」：Piper 神经语音整句读，语速与句间间隔在设置里调。
  朗读文本只取英文——SIO 的中文释义、出处书目与〔关键词〕标签，渲染时保留、朗读时剔除。
- **多行播放：暂停 / 继续 / 循环** - 词条顺序播放、AI 造句与短文、自定义短文都带
  同一组控件：播放中按「暂停」立即静音并记住读到哪一句，按「继续」从那一句重念；
  「循环」开关（⏭ 图标，状态存在设置里）让整篇读完后自动从头再来，直到按「停止」。
  文本转语音做不到句内暂停，所以继续是从被打断的那一句开头接上。数字模块另有一组
  同样的「暂停/继续」，恢复时从被打断的那一组数字重新开始。
- **内置家庭场景文库** - 仓库自带 25 篇「在家」子场景短文（`assets/seed/custom_home.json`），
  每篇 15–30 行，同一个动作连给三种说法（`I turned the big light off. / I switched the main
  light off.`），空行分簇；最后一篇是纯搭配清单（`put the kettle on`、`sort the recycling`）。
  AI 生成过的短文/造句也存了一份在 `assets/seed/ai_archive.json`。两者都在**首次启动、
  本地为空**时导入一次，之后不再覆盖；导入标记写在设置里，读者自己建的库永远不会被种子冲掉。
- **自定义短文** - 按**分组**组织（顶层是分组，含「未分组」，每行显示条数），
  组内是短文：写完即可点 🔊 读，也能「顺序播放 N 句」——在句号/问号/叹号/换行处
  断句逐句朗读，句间停顿取设置。正文里右键任意一句可以「从这里开始朗读」，从该句
  念到结尾。分组可新建/重命名/删除（删除时条目退回未分组，
  单条也可「移到其他分组」），数据存在本机设置里。旧版本按「短语」存的条目
  读取时一律按短文处理（没有标点就是一句），不需要手动迁移。
- **设置面板** - 导航栏底部的齿轮（原主题切换按钮的位置）：主题、本地词典管理、
  播放语速、短语/例句间隔都在这里。
- **多词典** — 同时加载多本词典联合查词，可逐本启用/停用。
- **发音** — 优先播放 `.mdd` 内的高保真原声；缺失时回退系统语音/在线音源。
  美音、英音双轨；`lead` / `read` 等同形异音词的多个读音分别提供。
- **音标（IPA）** — 48 条音标数据，与[剑桥音标表](https://dictionary.cambridge.org/help/phonetics.html)
  逐行对应（含 `/ɒ/ /ɜː/ /əʊ/` 等英音专有、`/ɝː/ /ɚ/ /oʊ/ /t̬/` 等美音专有）：发音要领、口型舌位、
  拼写规律、例词试听，以及与其它音标的组合发音（声母拼读、辅音连缀、尾音闭合、不送气浊化）。
  示范音是剑桥自己的原声、UK/US 分轨；单元音按「长元音 + 对应短元音」成对同排展示。
- **字母** — 26 个字母的标准发音（美/英双音，如 `Z` 的 `zee` / `zed`）与自然拼读规律。
- **数字** — 15 类数字表达方式（基数/序数/大数字/小数/分数/百分数/温度/倍数与次数/比例/年份/时刻/金额/
  电话号码/日期/零的读法），
  每个数字给出 🇬🇧 / 🇺🇸 两种读法，可分别试听；输入任意数字即时生成英语句子（`1,234` →
  one thousand two hundred and thirty-four，英音多一个 `and`）。词汇按**规律性**整理：1–12、13–19、
  整十、1st–12th、‑teenth/‑tieth 这些**不规则**形式逐个列卡（附拼写提示：forty 没有 u、fifth/ninth/
  twelfth、twenty→twentieth、y→ie），而 `21–99`、`21st–99th`、`hundred 以上` 只给**一条规则卡**
  （各附 3 个可试听样例），不逐个重复。日期类目另收录**12 个月份与 7 个星期**的全部词汇卡
  （含缩写 Jan. / Sept. / Wed.，以及 Wednesday 的 d 不发音、Tuesday 英 /ˈtjuːzdeɪ/ 等读音要点），
  每月/每周一张、可分别试听英美两音。训练模式随机出一组数字、**默认隐藏**，点「显示数字」再对照，
  朗读语速（×0.5–×1.5；Windows 系统语音的 **×1.0 = 教学语速**，Piper/Android/浏览器/录音的 ×1.0 = 各自自然语速）与数字之间的间隔
  （0–3 秒，滑到 0 即连读）可调并持久化；**「循环」**开关让整组朗读完自动从头再来（直到按「停止」，
  播放中改开关在本轮结束后生效），适合跟读与听写时反复磨耳朵；
  每组数量滑杆到 100，更多可在「自定义」里直接输入（最多 1000，列表懒加载渲染）。
  训练类型共 13 种：整数 / 大数字 / 小数 / 年份 / 序数词 / 分数 / 百分数 / 温度 / 时刻 / 货币 /
  日期 / 电话号码 / 混合。整数模式另有**多组连读**：每组随机 3–7 个数字（区间可调 2–12）一次念完，
  组内间隔可调到 0（连读），组与组之间用「组间」间隔隔开，适合听写练习；**组内间隔 = 0 时整组交给引擎念成一句**（连读），
  调大则逐个数字分开念、中间正好留出设定的秒数（逐词拼读模式同样按这个间隔逐词播放）。**同一组内尽量不重复**——先用该类型还没出现过的数字，可选值用尽后（例如一位整数只有 9 个）
  剩余名额按洗牌轮次补足，同一个数字不会紧挨着出现两次，界面会标注这组实际有几个不同值。
- **词频** — Top 20,000 词频榜单，支持自定义区间（如 `5000-6000`）、分页与跳页；
  区间设置持久化，重启后自动恢复。
- **生词本** — 分组收藏、助记笔记、分组颜色标签，本地持久化。
- **词条正文** — 多标签页（American / Etymology / Explanation / Examples）、
  全文可选可复制、正文与小喇叭链接联动发音。条目样式由渲染器的样式回调按标签/类名注入
  （`HtmlWidget` 不解析 `<style>`），内置 Dictionary.com 与 SIO 两套标记的规则；
  词典自带的 `.css` 不参与渲染——SIO 的 `zh_cn{display:none}` 需要它的 JS 才能切换，直接套用会把中文藏死。
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

音标、字母、数字、词频四个模块在前端完全离线可用，不依赖后端。

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

词典文件（约 1.7 GB）**不纳入版本控制**，需自行准备：

```
Dictionary.com 20260913_hahaya/
├── Dictionary.com 20260913.mdx      # 词条正文（必需）
├── Dictionary.com 20260913.mdd      # 发音音频（可选）
└── dcom-mdx-style.css               # 词条样式（可选）
```

桌面端/Android 首次启动会**自动探测** `.mdx`，探测顺序为

1. `DICT_DIR` 环境变量指向的目录（多个用 `;` 分隔，与后端同一变量名称）；
2. 当前工作目录；
3. 程序所在目录及其各级上级目录（因此 `build/windows/x64/runner/Release/` 也能找到仓库根目录下的词典）。

每个目录还会再看**一层子目录**，所以「一本词典一个文件夹」的布局（如
`SIO雙向雙解詞典 v3.3/`）和把 `.mdx` 平铺在一个目录里都能被发现；同名 `.mdd` / 目录内任意 `.css`
一并登记。探测只在登记表为空时自动进行，之后可在「词典」页点「探测词典目录」重新扫描，
或直接手动导入任意 `.mdx`。登记表存放在应用数据目录（Windows：`%APPDATA%\…\local_dict\dict_app.db`）。

后端另有 `--dir` 参数（与 `DICT_DIR` 等价）。

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
│   ├── numbers/      # 数字读法引擎（拼写器 + 单词片段播放 + 训练生成器）
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
├── audio/numbers/    # 数字单词片段 165 × 美/英音（拼句读任意数字，见「数字音频的来源」）
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
flutter test             # 单元与 Widget 测试（71 项）
dart analyze server      # 后端静态分析
```

### 真机自检（发音引擎）

主机的 `flutter test` 覆盖不了「*这台设备*能不能把数字念出来」——那要真机。把它交给一个独立入口 + 一条命令：

```bash
tool/android_smoke.sh                  # 唯一连接中的设备
tool/android_smoke.sh -s PLK110        # 多台设备时指定
tool/android_smoke.sh -s emulator-5554 --uninstall
```

脚本用 `flutter run -t lib/smoke_main.dart` 编译、安装、启动，抓取 `SMOKE …` 行判定通过/失败，手机上同时显示同一份结果与顺手播出的声音：

- **录音拼接**：只用包内资源，刚装好的应用就能测；
- **Piper**：装了模型就测（`SMOKE ok piper-uk 23296 samples @ 22050 Hz`），没装报 `skip`——这是正常状态，不会误判失败；
- **系统语音**：让平台语音念同一句话（没有英语语音的设备会如实报 `skip`）。

Piper 的模型得进应用私有目录，两条路落点相同（`/data/user/0/<包名>/files/tts-models/piper/<us|uk>`）：

- **通常不需要**：正式包自带模型，首次启动自动解包（见[发布打包](#发布打包含-piper-模型)）；
- **调试包/旧包没有内置**：在应用里「安装模型…」选 `piper.zip` 导入；
- **已经 root**（`adb shell` 里 `su` 可用）：不必点手机上的文件选择器，直接推进去——

```bash
python tool/fetch_piper_models.py --zip-only          # 生成 tts-models/piper.zip
python -c "import zipfile; zipfile.ZipFile('tts-models/piper.zip').extractall('build/piper_extract')"
adb push build/piper_extract/. /sdcard/Download/piper_extract
adb shell "su -c 'mkdir -p /data/user/0/com.example.local_dict/files/tts-models/piper'"
adb shell "su -c 'cp -rf /sdcard/Download/piper_extract/. /data/user/0/com.example.local_dict/files/tts-models/piper/'"
adb shell "su -c 'chown -R \$(stat -c %u /data/user/0/com.example.local_dict):\$(stat -c %u /data/user/0/com.example.local_dict) /data/user/0/com.example.local_dict/files/tts-models'"
adb shell "su -c 'rm -rf /sdcard/Download/piper_extract'"
```

（`su -c` 那段务必保持 `adb shell "su -c '…'"` 这个引号形式：引号要是被本地 shell 吃掉，`su` 会停在等待输入上。）

`lib/smoke_main.dart` 是**独立入口**（不是应用代码），所以应用里没有测试代码；`--uninstall` 会在结束后卸掉临时装的 APK。

> 自检装的是 **smoke 入口**，而且 `flutter run -t` 会覆盖同一份 `build/app/outputs/flutter-apk/app-debug.apk`——所以跑完想用回真正的应用，重新出一份再装：
> ```bash
> flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
> ```
> 数据不会丢（模型、生词本都在 `/data/user/0/<包名>/` 里，装同签名的包是覆盖升级）。

Windows 上请在 Git Bash / MSYS2 / cmd 里运行，**不要在 WSL 里**：本机的工具链是 Windows 那一份（WSL 会报 `unable to extract Dart SDK`），脚本也会直接提示这一点。

### 发布打包（含 Piper 模型）

词典文件与 Piper 模型都**不进版本库**（体积与授权），它们是**运行时资源**：应用在各平台约定的位置读取。
所以"发布版" = 构建产物 + 放在正确位置的模型。一条命令把两件事一起做：

```bash
python tool/fetch_piper_models.py      # 首次准备：约 70 MB，落在 tts-models/（已 gitignore）
tool/package_release.sh windows        # 或 web / apk / all；加 --no-build 只重新摆放模型
```

| 目标 | 产物 | 模型放哪 | 怎么发布 |
|---|---|---|---|
| windows | `build/windows/x64/runner/Release/` | **同目录**下的 `tts-models/`（脚本自动拷入） | 整个 Release 文件夹打包分发 |
| web | `build/web/` | `build/web/tts-models/`（脚本自动拷入） | 连同静态站点部署，nginx 片段见[部署指南 §5.3](docs/WEB_DEPLOYMENT.md#53-piper-模型数字训练的piper-神经语音引擎) |
| apk | `build/release/app-<abi>-release.apk`（按 ABI 拆分，每个约 105–110 MB） | **已内置**：构建时把 `tts-models/piper.zip` 打进 `assets/`，首次启动由原生侧解到私有目录 | 只发 APK。**安装用 `tool/package_release.sh install`**：它按设备的 ABI 选包，避免拿通用包（versionCode 1）覆盖拆分包（2000+）报 downgrade |

**模型随 APK 走**：Gradle 任务 `copyPiperModels` 把 `tts-models/piper.zip` 放进 assets（没准备模型时构建照常成功，应用自动回退），
APK 装好第一次打开就解压到 `/data/user/0/<包名>/files/tts-models/piper/`，**不需要电脑、不需要下载、不需要导入**。
没有内置模型时，手机既没有英语系统语音、又没有模型，整句朗读只能退到录音拼接（逐词录音，听感是一个一个单词）——
这正是"安装即用"要解决的问题。通用包要塞 4 套 sherpa-onnx（约 280 MB），所以 release 仍用 `--split-per-abi`。

**没有模型也能发**：整句朗读会自动换引擎（Piper 缺失 → 系统语音 → 自带录音拼接），训练区写明当前用的是谁；
所以只想验证功能的构建不必先准备模型。

> `android/app/build.gradle.kts` 里 release 目前仍用 **debug 签名**（Flutter 模板默认，带 TODO）。
> 正式分发前换成自己的 keystore——换签名后已装应用的数据会被清空，模型要重新导入一次。

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

### 数字怎么读：整句朗读的三档引擎 + 逐词拼读

训练区里「整句朗读」旁边有一个开关选**用哪个引擎念整句**，只有两档可选：**系统语音**（默认）与 **Piper 神经语音**（选择会持久化）。
引擎说不出话时**不会**把数字拆成单词念：按 `选择 → Piper → 系统语音 → 自带录音拼接` 换引擎整句念完，
其中**录音拼接**是内置兜底（永远可用、无接缝），不出现在开关里——它的音色和逐词模式用的是同一批录音，没人会主动选它；
只有所有引擎都失败才退到逐词播放，而「逐词拼读」模式照旧逐词播放（它就是听写用的）。

| 引擎 | 声音来自 | 连读/韵律 | 离线 | 三端一致性 |
|---|---|---|---|---|
| **系统语音**（默认） | 宿主的语音合成：Windows 用 **OneCore 自然语音**（Narrator 那批：Mark / Jenny / Aria / Hazel / George…）否则 **SAPI 桌面语音**（Zira 等）；Android 用 `TextToSpeech`；Web 用 `speechSynthesis` | 真·连读（整句一次合成） | Windows/Android 是；浏览器上 `Google US/UK English` 需要联网（界面会注明） | 音色随机器而异 |
| **Piper 神经语音** | 随应用分发的 **Piper**（VITS）模型在本机推理 | 真·连读 | ✅ 完全离线 | ✅ **同一模型、同一音色**：Windows / Android / 浏览器（WebAssembly） |
| **录音拼接**（内部兜底，不在开关里） | 模块自带的 330 条单词录音，在**内存里拼成一句**再交给播放器播一次 | 逐词读音，但**没有接缝** | ✅ | ✅ 三端逐字节相同（拼接是纯 Dart，有单测） |
| 逐词拼读（听写模式） | 同上，但不拼接：一个词一个词播、词间留 200 ms 与设定间隔 | 逐词，有断口 | ✅ | ✅ |

同一句话的客观对比（见 `tool/` 时代的测量记录）：系统语音整句 2.20 s / 0 处停顿，逐词 4.92 s / 6 处 ≥80 ms 断口。
语速滑杆对所有引擎都生效（系统语音走 SSML `prosody rate` / SAPI Rate / `setSpeechRate` / 浏览器 `rate`，Piper 走模型自身的 `speed`，录音走播放器倍速）。

### 语速：×1.0 是「教学语速」，不是母语语速（Windows 系统语音路径）

Piper、Android TTS、浏览器语音的速率都是连续量，直接照滑杆值走（代码里也没有二传：`number_speaker` 把滑杆值原样交给各引擎，
`windowsEngineRateFor` 只在 Windows 的两个语音实现里被调用）。**Windows 系统语音不是**：
`lib/core/audio/speech_rate.dart`（纯函数、有单测）专门处理这条路径 —— 它的速率控制是分级的，
而且这里有个刻意的取舍：**母语者的自然语速不该是这个用途的中性点**。母语者念
"one thousand two hundred and thirty-four" 只要 1548 ms，而你要一边听一边做心算，
那个速度属于「快」的一端。所以滑杆的 ×1.0 定义为**教学语速 = 自然语速的一半**：

| 滑杆 | ×0.50 | ×0.75 | **×1.00** | ×1.25 | ×1.50 |
|---|---|---|---|---|---|
| 相对母语者 | 0.23× | 0.33× | **0.50×** | 0.64× | 0.71× |
| 实测时长 | 6.805 s | 4.735 s | **3.100 s** | 2.429 s | 2.166 s |

（同一句话，OneCore「Microsoft David」；母语者基准 1.548 s。旧版本 ×1.0 就是 1.548 s。）

OneCore 的 prosody 是 **11 档分级**，不是线性的：

| prosody | 1–5% | 8–15% | 18–30% | 35–45% | 50–60% | 70–80% | 90–100% | 110–120% | 130–150% | 175% | 200% |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 相对母语者 | 0.50× | 0.57× | 0.64× | 0.71× | 0.80× | 0.90× | 1.00× | 1.12× | 1.24× | 1.39× | 1.52× |

所以是查表就近取值（对数距离，并列取更慢的一档），而不是把滑杆值当百分比直接传 ——
后者（`percent = rate * 100`）只会落在最平的中间四档，滑杆几乎推不动。

**慢于 0.50× 的部分用词间停顿实现**：prosody 到 5% 就到底了，再慢靠 SSML `<break>`
在词间留白（实测：无停顿 1548 ms，150/300/500 ms 间隔分别 2279/2779/3380 ms）。
**不换声线、不降音调**，每个词仍是自然发音，只是词间留白。SAPI 回退另有一张表
（`SpVoice.Rate` -10…10 实测跨 3.0× 慢到 3.1× 快），但 SAPI 在这套桥接里没有停顿支持，
下限是硬的。

> 升级兼容：语速是持久化的，旧版本的 ×1.0 等于自然语速，所以旧值**乘 2** 迁移
> （旧的 0.5 就是现在的 1.0，听感不变），并写标记避免重复迁移。

**想换更好听的人声**：

1. Windows：设置 → 时间和语言 → 语音 → 管理语音 → **添加语音** → English (United States) / (United Kingdom)：
   会装上新一代 OneCore 语音，模块按 LCID/tag 优先匹配，并**优先于旧版桌面语音**被选中；
   或安装第三方 **SAPI5** 语音（CereProc、Ivona、RHVoice 等），它们同样出现在 SAPI 列表里；
2. Android：设置 → 系统 → 语言和输入 → 文字转语音输出，选引擎/语言，或另装一个 TTS 引擎；
3. Web：音色由浏览器决定——Chrome 的 `Google US/UK English` 是**在线语音**，界面会注明「这条语音要联网」，
   而系统的本地语音（如 Windows 上的 Microsoft David/Zira）离线可用，模块优先选后者。

模块的选择顺序（`lib/core/audio/voice_choice.dart`，纯函数、有单测）：
**请求口音的离线语音 → 任意英语离线语音 → 请求口音的在线语音 → 任意英语在线语音 → 无（用录音）**。
离线排在口音前面是刻意的：浏览器与部分 Android 引擎会给出云端语音，一旦断网就会在朗读中途哑掉，
而音色不完全是小事。

#### Piper 模型：一条命令装好，三端同一音色

模型不进仓库（每档约 35 MB，含 espeak-ng 数据），用一个脚本准备好：

```bash
python tool/fetch_piper_models.py            # 美音 + 英音（默认 lessac / alan 的 int8 模型）
python tool/fetch_piper_models.py --check    # 只看装了没有，并重建文件清单
python tool/fetch_piper_models.py --voice us=en_US-amy-medium-int8   # 换音色
```

装好的目录（`files.txt` 是给浏览器用的文件清单，工具自动生成）：

```
tts-models/piper/
├── us/{model.onnx, model.onnx.json, tokens.txt, espeak-ng-data/, files.txt}
└── uk/{…}
```

各端去哪里找它——**与词典同一套规则**（`TTS_MODEL_DIR` 环境变量 → 当前目录 → 程序目录及其上级 → 应用数据目录）：

| 端 | 放哪里 | 说明 |
|---|---|---|
| Windows | 程序目录或仓库根目录下的 `tts-models/`，也可用 `TTS_MODEL_DIR` | 从 `build/windows/x64/runner/Release/` 往上能找到仓库根目录的 `tts-models/` |
| Android | **包内自带**：APK 的 `assets/piper.zip` 在首次启动时解到 `/data/user/0/<包名>/files/tts-models/piper/`；换声/更新用训练区的「**安装模型…**」 | **不能用 `adb push`/文件管理器放进 `Android/data/…/files`**：Android 11+ 的作用域存储让应用读不到别的工具写进去的文件，只认应用自己解出来的那份 |
| Web | 站点根下的 `/tts-models/` | 浏览器不能列目录，按 `files.txt` 逐个取（约 35 MB/档，浏览器缓存后不再下载）；nginx 配置见部署指南 |

`tts-models/piper.zip` 就是给 Android 导入用的那份压缩包（`--zip-only` 可单独重建，不必重新下载模型）。

模型缺失时训练区会显示「未安装模型：…」并自动改用别的引擎，不会报错。

> **WebAssembly 的特殊之处**：浏览器里跑的库读的是 Emscripten 自己的文件系统，HTTP 路径对它没有意义
> （模型明明能 `fetch` 到，它仍然报 "does not exist"）。所以 Web 端会把清单里的文件全部取下来写进那个
> 文件系统（`FS_createPath` / `FS_createDataFile`）再加载模型——这段是平台差异，藏在 `piper_model_store_web.dart` 里。

### 数字表达的覆盖范围

每个类别都按「**不规则 / 固定说法逐个列卡，有规律的给一条规则卡**」整理，规则卡附 3 个左右可试听样例：

| 类别 | 规则卡（规律） | 单独列出的形式 |
|---|---|---|
| 基数词 | `21–99`（十位+个位）、`hundred 以上`（英 and / 美省略） | 0–12、13–19、整十、hundred、thousand |
| 序数词 | `21st–99th`（只变最后一段） | 1st–12th、13th–19th、整十序数、100th/1,000th/1,000,000th |
| 大数字 | `三位一组`（thousand/million/billion/trillion，million 前不加 -s） | 三个刻度词 + 4 个样例数字 |
| 小数 | `0 的读法`（nought / zero / oh）、`逐位读`（3.14 = three point one four） | 0.5、3.14、-1.5、0.05、0.007、1,234.56 |
| 分数 | `分母的规律`（2=half、4=quarter、其余序数词+‑s）、`over 的用法`（分母>10）、`of 搭配与弱读`（a half / a quarter） | 1/2、1/3、3/4、2/5、7/8、1 1/2 |
| 百分数 | `per cent / percent`（英式两词）、`X percent of`（接复数名词） | 25%、99.9%、100%、0.5%、150% |
| 年份 | `2010 起两种读法`、`年代`（the nineties / the two thousands）、`BC / AD` | 1999、1905、1900、2005、2026、1066、1100 |
| 时刻 | `past / to 规则`（quarter / half / N past / N to）、`a.m. / p.m.` | 3:00、3:15、3:30、3:45、7:05、15:30、12:00、0:00 |
| 货币 | `符号与单位`、`口语省略单位`（twelve fifty）、`复数位置` | $12.50、£3.99、€20、$0.99、$1、£0.50、£1.50、$2,000,000 |
| 电话号码 | `分组与停顿`、`double / triple`（英）、`800 号段`（1-800 = one eight hundred） | +44 20 7946 0958、0755-1234-5678、007、203、1001、1-800-555-0199 |
| 日期 | `英美写法不同`（03/05 的歧义）、`星期与介词`（on / in）、`世纪与年代` | 2026-10-08、2026-01-01、2026-05-03 |
| 温度 | `摄氏度 / 华氏度`（°C = Celsius/Centigrade、°F = Fahrenheit，口语常省略温标）、`零下的说法`（minus five degrees / five degrees below zero） | 0°C、25°C、1°C、-5°C、37°C、98.6°F |
| 倍数与次数 | `once / twice / N times`（1 次 once、2 次 twice）、`倍数比较`（twice as much as）、`频率表达`（once a week / once every two weeks） | 1x、2x、3x、1.5x、once a week、twice a day、three times a week、once every two weeks |
| 比例 | `「:」读 to`（2:1 = two to one，尺寸用 by）、`in / out of`（9 out of 10） | 2:1、3:2、4:3、1 in 10、9 out of 10 |
| 零的读法 | `五套读法`（zero / nought / oh / nil / nothing / love） | 0、0(电话)、0.5、3-0、40-0、0°C |

尚未建栏目、引擎也不支持的表达方式（需要新词汇片段才能做）：运算（two plus three equals five）、
约数（a dozen、a couple、about twenty）、单位换算（60 miles per hour）。

### 数字音频的来源

数字是**开放集合**（没有人能预录 `1,234,567`），但它的读法由**有限单词**拼出来：
`assets/audio/numbers/<word>_uk.wav` / `<word>_us.wav` 就是那 165 个词（`zero`…`nine`、
`twenty`…`ninety`、`hundred`…`trillion`、序数词、分数分母、`point` / `and` / `over` / `oh` /
`nought` / `double`、货币与月份名）的单词语音，播放时**逐词拼接**，因此任意数字都能离线读出来，
且英美两条轨各自独立——两者差别不只在口音，句子本身就不一样（英音 `one hundred and twenty-three`、
`nought point five`；美音去掉 `and`、读 `zero point five`）。

```bash
python tool/generate_number_audio.py --check              # 只列词表，不写文件
python tool/generate_number_audio.py                      # 重新生成全部片段
python tool/generate_number_audio.py --only thirds --force # 只补某几个词
python tool/generate_number_audio.py --source edge         # 换用神经语音（当前被 403 挡住）
```

音源是词典发音接口（`type=1` 英音 / `type=2` 美音，与应用在线回退播放的同一路），
只有 `sixths`（英音）与 `sevenths`（美音）这两条它拒绝，而这两个词的读音**英美无差别**，
脚本用另一条口音顶替并在结尾打印 `Copied across accents`。

**切词规则**（`utterance_span`）：源文件里单词藏在 0.4 s 前导静音、偶尔第二遍、以及鼻音/摩擦音
很长的弱尾之后（`one` = /wʌn/ 尾巴拖 0.3 s），所以句子是**量出来**再切的——10 ms RMS 帧，
以**第 95 百分位**（不是最大值）下 45 dB 为静音线，间隔 < 150 ms 属于同一个词，取**能量最大且不短于
120 ms 的那一段**（不是第一段），两侧各留 40 ms，5 ms 淡入淡出，RMS 归一到 −20 dBFS、峰值上限 −1 dBFS、
24 kHz 16-bit 单声道 **WAV**（PCM：整句拼接就是把采样直接接起来，三端播的是同一批字节）。
每条片段最后都跟源录音做**相关性校验**（在切片位置 Pearson ≥ 0.9），不合格就不写盘。

两个曾经真的踩过的坑，别重犯：

- **别用 ffmpeg 的 `silenceremove`+`areverse` 去切词**：−40 dB 的门限会把弱尾（`one`→"wuh"）和
  弱起音（/w/ /h/ /ð/）一起切掉，而且它不会告诉你切了多少——片段看起来仍是"正常的一小段"。
  26 条片段因此少了 20%–50% 的发音，是逐个跟源录音比语音跨度才查出来的。
- **取"第一段有声区间"会拿到爆音**：`hundredth` 美音录音是 20 ms 爆音 + 0.5 s 静音 + 单词，
  按第一段取会得到 0.07 s 的空片段。

播放侧同样有一条硬规则：**不要用 `Stream.timeout(onTimeout: () { … })`**。
那个回调必须返回流的元素类型，`() { … }` 能编过、运行时抛
`type '() => Null' is not a subtype of '(() => FutureOr<AudioEvent>)?'`，于是等待**立刻返回**，
下一个词马上顶替当前音源——听感就是每个词只念出开头一小截（数字朗读曾整句只花 300 ms）。
现在用 `Future.any` 与延时赛跑（`audio_manager_*.dart` 里 `playSpeechClip` 有注释），
并用「时长 + 1.5 s 下限」的兜底，保证不会把词切短。

词表是两侧共同遵守的契约：Python 侧 `NUMBER_WORDS` 决定生成哪些片段，Dart 侧
`lib/core/numbers/number_audio.dart` 决定能播哪些词，`test/number_module_test.dart` 会同时校验
「两边词表一致」「每个词两个口音都有片段」「拼写器产出的每个词都有片段」，任一侧改名都会直接失败。
播放走 `lib/core/audio/speech_clip_player.dart` 的接口，`NumberSpeaker` 只依赖它，
因此词序、电话分组停顿、训练间隔与「停止」都能在没有声卡的情况下被单测钉住。

## 文档

- [Web 端部署指南](docs/WEB_DEPLOYMENT.md) — Docker、单源 + TLS、静态托管、API 契约、故障排查
- [后端源码](server/dict_server.dart) — 接口实现
