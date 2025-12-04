import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/data_service.dart';
import '../models/meeting_models.dart';
import 'meeting_selection_screen.dart';
import 'meeting_room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final service = DataService();

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("APP 使用說明"),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("1. 建立會議 (召集人)：\n   輸入會議資訊，並匯入人員 CSV 檔案。"),
              SizedBox(height: 10),
              Text("2. 參加會議：\n   選擇既有的會議室進入，並從名單中選擇您的身分。"),
              SizedBox(height: 10),
              Text("3. 檔案格式：\n   請下載範例檔案，格式為：學號,姓名,身分。"),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("了解")),
        ],
      ),
    );
  }

  void _showCreateMeetingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const CreateMeetingDialog(),
    ).then((_) => setState(() {}));
  }

  void _handleJoinMeeting() {
    if (service.meetings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("目前沒有任何已建立的會議，請先建立！")));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingSelectionScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("會議投票系統"),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _showHelpDialog, tooltip: "說明")
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.meeting_room, size: 80, color: Colors.indigo),
            const SizedBox(height: 30),
            SizedBox(
              width: 220,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text("建立會議 (召集人)", style: TextStyle(fontSize: 16)),
                onPressed: _showCreateMeetingDialog,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text("參加會議", style: TextStyle(fontSize: 16)),
                onPressed: _handleJoinMeeting,
              ),
            ),
            const SizedBox(height: 20),
            if (service.meetings.isNotEmpty)
              Text("目前系統有 ${service.meetings.length} 場會議", style: const TextStyle(color: Colors.green)),
          ],
        ),
      ),
    );
  }
}

class CreateMeetingDialog extends StatefulWidget {
  const CreateMeetingDialog({super.key});

  @override
  State<CreateMeetingDialog> createState() => _CreateMeetingDialogState();
}

class _CreateMeetingDialogState extends State<CreateMeetingDialog> {
  final titleController = TextEditingController(text: "");
  final hostController = TextEditingController(text: "");
  List<User> tempUsers = [];
  String? _importStatus;

  Future<void> _downloadTemplate() async {
    const String csvContent = "學號,姓名,身分\nA100,陳小明,出席\nA101,林大華,紀錄\nA102,王小美,列席\n";
    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/人員名單範例.csv';
      final file = File(path);
      await file.writeAsString(csvContent);
      await Share.shareXFiles([XFile(path)], text: '請使用此格式建立人員名單');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("匯出失敗: $e")));
      }
    }
  }

  Future<void> _pickAndImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        final content = await file.readAsString();
        _parseCsv(content);
      }
    } catch (e) {
      setState(() {
        _importStatus = "讀取失敗，請確認檔案格式 (UTF-8 CSV)";
      });
    }
  }

  void _parseCsv(String content) {
    final lines = LineSplitter.split(content).toList();
    final newUsers = <User>[];
    int successCount = 0;

    for (var i = 0; i < lines.length; i++) {
      if (i == 0 && lines[i].contains("學號")) continue;

      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split(',');
      if (parts.length >= 3) {
        newUsers.add(User(
          id: DateTime.now().microsecondsSinceEpoch.toString() + i.toString(),
          studentId: parts[0].trim(),
          name: parts[1].trim(),
          role: parseRole(parts[2]),
        ));
        successCount++;
      }
    }

    setState(() {
      tempUsers.addAll(newUsers);
      _importStatus = "成功匯入 $successCount 筆資料";
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("建立新會議"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: "會議名稱", hintText: "例：期中專案檢討")),
              TextField(controller: hostController, decoration: const InputDecoration(labelText: "主持人姓名", hintText: "例：王大明")),
              const SizedBox(height: 20),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("人員名單", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("下載範例"),
                    onPressed: _downloadTemplate,
                  )
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickAndImportFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text("從 CSV 檔案匯入名單"),
                ),
              ),
              if (_importStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_importStatus!, style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              Container(
                height: 150,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                // 修正：使用 isNotEmpty 判斷
                child: tempUsers.isEmpty
                    ? const Center(child: Text("尚未加入人員"))
                    : ListView.builder(
                  itemCount: tempUsers.length,
                  itemBuilder: (ctx, idx) {
                    final u = tempUsers[idx];
                    return ListTile(
                      dense: true,
                      title: Text("${u.name} (${u.studentId})"),
                      subtitle: Text(getRoleText(u.role)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        onPressed: () => setState(() => tempUsers.removeAt(idx)),
                      ),
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
        ElevatedButton(
          onPressed: () {
            // 修正：使用 isNotEmpty
            if (titleController.text.isNotEmpty && hostController.text.isNotEmpty) {
              DataService().createMeeting(titleController.text, hostController.text, tempUsers);
              Navigator.pop(context);
              final host = DataService().users.firstWhere((u) => u.role == UserRole.host);
              Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingRoomScreen(currentUser: host)));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("請填寫完整資訊")));
            }
          },
          child: const Text("建立並進入"),
        ),
      ],
    );
  }
}