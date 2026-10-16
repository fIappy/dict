import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../core/models/dictionary_info.dart';
import '../../core/services/dictionary_service.dart';
import '../../providers/dictionary_provider.dart';

class DictionaryManagerScreen extends StatefulWidget {
  const DictionaryManagerScreen({super.key});

  @override
  State<DictionaryManagerScreen> createState() => _DictionaryManagerScreenState();
}

class _DictionaryManagerScreenState extends State<DictionaryManagerScreen> {
  final DictionaryService _service = DictionaryService();
  bool _isImporting = false;

  bool get _supportsLocalDictionaries => _service.supportsLocalDictionaries;

  bool get _backendConnected => _service.isBackendConnected;

  int _totalEntries(List<DictionaryInfo> dicts) =>
      dicts.fold<int>(0, (sum, d) => sum + d.entryCount);

  Future<void> _pickAndImportDictionary(BuildContext context) async {
    final dictProvider = context.read<DictionaryProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      // On Android the picker returns a cache copy of each file inside its own
      // timestamped directory, so a sibling .mdd can never be discovered there.
      // Both files therefore have to be selected in the same pass.
      // file_picker 13 returns the selection directly and is multi-select.
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择词典文件：.mdx 主文件必选，同名词典请一并选中 .mdd',
        type: FileType.custom,
        allowedExtensions: ['mdx', 'mdd'],
      );

      final picked = files
          .map((f) => f.path)
          .whereType<String>()
          .toList(growable: false);
      if (picked.isEmpty) return;

      final mdxPaths =
          picked.where((x) => x.toLowerCase().endsWith('.mdx')).toList();
      final mddPaths =
          picked.where((x) => x.toLowerCase().endsWith('.mdd')).toList();

      if (mdxPaths.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('.mdd 只是发音资源，请同时选中同名的 .mdx 主文件'),
            backgroundColor: Color(0xFFEF6C00),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isImporting = true);

      var imported = 0;
      final missingAudio = <String>[];
      try {
        for (final mdx in mdxPaths) {
          final base = p.basenameWithoutExtension(mdx).toLowerCase();
          String? pairedMdd;
          for (final mdd in mddPaths) {
            if (p.basenameWithoutExtension(mdd).toLowerCase() == base) {
              pairedMdd = mdd;
              break;
            }
          }

          final info = await dictProvider.importDictionary(
            mdxPath: mdx,
            mddPath: pairedMdd,
          );
          imported++;
          if (!_service.resourceAvailable(info.mddPath)) {
            missingAudio.add(p.basenameWithoutExtension(mdx));
          }
        }
      } finally {
        if (mounted) setState(() => _isImporting = false);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            missingAudio.isEmpty
                ? '已导入 $imported 本词典，均已配对发音库 .mdd'
                : '已导入 $imported 本词典；${missingAudio.join("、")} 未找到同名 .mdd，'
                    '发音将回退到在线音源（离线时无声）',
          ),
          backgroundColor:
              missingAudio.isEmpty ? Colors.green[700] : const Color(0xFFEF6C00),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('导入词典失败: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  /// Registers every `.mdx` the probe folders hold — `DICT_DIR`, the working
  /// directory, and the program's folder with its ancestors.
  Future<void> _autoImportDetected(BuildContext context) async {
    final dictProvider = context.read<DictionaryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isImporting = true);
    List<DictionaryInfo> registered;
    try {
      registered = await dictProvider.autoImportDetected();
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }

    messenger.showSnackBar(
      registered.isEmpty
          ? const SnackBar(
              content: Text('未探测到新的 .mdx 词典；'
                  '可设置 DICT_DIR、把词典放进当前目录或程序目录'),
            )
          : SnackBar(
              content: Text('已加载 ${registered.length} 本词典：'
                  '${registered.map((d) => d.name).join("、")}'),
              backgroundColor: Colors.green[700],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dictProvider = context.watch<DictionaryProvider>();
    final dicts = dictProvider.allDictionaries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地词典管理', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新加载词典',
            onPressed: () => dictProvider.initialize(),
          ),
        ],
      ),
      body: _isImporting
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在解析并索引本地词典，请稍候...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top Action Card
                Card(
                  elevation: 0,
                  color: isDark ? const Color(0xFF1E2430) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.library_books_rounded, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '已安装 ${dicts.length} 本词典',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_supportsLocalDictionaries)
                          Text(
                            '支持 MDict (.mdx / .mdd) 格式本地词典，支持多本词典联合查词、发音资源提取与样式渲染。',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _backendConnected
                                        ? Icons.cloud_done_rounded
                                        : Icons.cloud_off_rounded,
                                    size: 16,
                                    color: _backendConnected
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _backendConnected ? '已连接后端词典服务' : '未连接后端词典服务',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _backendConnected
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _backendConnected
                                    ? '词典由后端提供（${dicts.length} 本，'
                                        '共 ${_totalEntries(dicts)} 条词条）。'
                                        '网页版无法导入本地文件，请把 .mdx/.mdd 放入后端词典目录后重启服务。'
                                    : '后端地址：${_service.backendBaseUrl ?? "未配置"}\n'
                                        '请先启动后端（dart run server/dict_server.dart），'
                                        '或在网址后追加 ?api=http://主机:端口 指定后端。'
                                        '音标、字母与词频功能不受影响，可离线使用。',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        if (_supportsLocalDictionaries)
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('导入本地词典 (.mdx)'),
                                onPressed: () => _pickAndImportDictionary(context),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: const Text('探测词典目录'),
                                onPressed: () => _autoImportDetected(context),
                              ),
                            ],
                          )
                        else
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重新检测后端'),
                            onPressed: () => dictProvider.refreshDictionaries(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Dictionary List
                const Text(
                  '已加载的词典列表',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),

                if (dicts.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.folder_open_rounded, size: 56, color: theme.hintColor),
                          const SizedBox(height: 12),
                          const Text('暂无已添加的词典'),
                          if (_supportsLocalDictionaries) ...[
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: () => _autoImportDetected(context),
                              child: const Text('探测词典目录（DICT_DIR / 当前目录 / 程序目录）'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  for (final info in dicts)
                    _buildDictionaryCard(context, info, theme, isDark, dictProvider),
              ],
            ),
    );
  }

  Widget _buildDictionaryCard(
    BuildContext context,
    DictionaryInfo info,
    ThemeData theme,
    bool isDark,
    DictionaryProvider dictProvider,
  ) {
    final service = _service;
    final hasMdd = service.resourceAvailable(info.mddPath);
    final hasCss = service.resourceAvailable(info.cssPath);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isDark ? const Color(0xFF1E2430) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: info.isEnabled
              ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
              : (isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              info.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: info.isEnabled ? null : theme.disabledColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (info.entryCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${info.entryCount} 词条',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.mdxPath,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: info.isEnabled,
                  onChanged: (val) {
                    dictProvider.toggleDictionary(info.id, val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Metadata Chips
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildFeatureChip(
                  hasMdd ? '含配套音频库 (.mdd)' : '无独立音频库',
                  hasMdd ? Colors.green : Colors.grey,
                  hasMdd ? Icons.audiotrack_rounded : Icons.music_off_rounded,
                  isDark,
                ),
                _buildFeatureChip(
                  hasCss ? '含专用样式表 (.css)' : '默认排版样式',
                  hasCss ? Colors.blue : Colors.grey,
                  Icons.style_rounded,
                  isDark,
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(),

            // Actions. Removal is filesystem-owned, so it is native-only.
            if (_supportsLocalDictionaries)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    label: const Text('移除', style: TextStyle(color: Colors.red, fontSize: 13)),
                    onPressed: () => _confirmDelete(context, info, dictProvider),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(String label, Color color, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, DictionaryInfo info, DictionaryProvider dictProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除词典'),
        content: Text('确定要从列表中移除词典 "${info.name}" 吗？（本地原文件不会被删除）'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('移除'),
            onPressed: () async {
              Navigator.pop(ctx);
              await dictProvider.deleteDictionary(info.id);
            },
          ),
        ],
      ),
    );
  }
}
