import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ---------------------------------------------------------------------------
// 1. 資料模型 (Data Models)
// ---------------------------------------------------------------------------

enum UserRole {
  host, // 主席/主持人
  clerk, // 紀錄
  attendee, // 出席 (有投票權)
  observer, // 列席/旁聽 (無投票權)
}

// 簡單的 String 轉 Enum 輔助函式
UserRole _parseRole(String roleStr) {
  final cleanStr = roleStr.trim();
  if (cleanStr.contains('主') || cleanStr.contains('host')) return UserRole.host;
  if (cleanStr.contains('紀錄') || cleanStr.contains('clerk')) return UserRole.clerk;
  if (cleanStr.contains('旁') || cleanStr.contains('列') || cleanStr.contains('observer')) return UserRole.observer;
  return UserRole.attendee; // 預設為出席
}

String _getRoleText(UserRole role) {
  switch(role) {
    case UserRole.host: return "主席";
    case UserRole.clerk: return "紀錄";
    case UserRole.attendee: return "出席";
    case UserRole.observer: return "列席";
  }
}

class User {
  final String id;
  final String name;
  final UserRole role;
  String studentId; // 學號

  // 動態狀態
  bool isSignedIn; // 是否已簽到
  bool hasVotingRight; // 是否已被清點並賦予投票權

  User({
    required this.id,
    required this.name,
    required this.role,
    this.studentId = '',
    this.isSignedIn = false,
    this.hasVotingRight = false,
  });
}

class VoteOption {
  final String id;
  final String text;
  int count;

  VoteOption({required this.id, required this.text, this.count = 0});
}

class VoteSession {
  final String id;
  final String title;
  final List<VoteOption> options;
  final bool isAnonymous;
  final int? durationSeconds;

  // 紀錄當下具投票權的總人數 (分母)
  final int eligibleVotersCount;

  bool isActive;
  DateTime? startTime;
  DateTime? endTime;

  Set<String> votedUserIds = {};

  // 紀錄誰投了哪個選項 (用於記名投票顯示) - Map<UserId, OptionId>
  Map<String, String> namedVotes = {};

  VoteSession({
    required this.id,
    required this.title,
    required this.options,
    required this.isAnonymous,
    required this.eligibleVotersCount,
    this.durationSeconds,
    this.isActive = true,
    this.startTime,
  });
}

class Meeting {
  final String id;
  final String title;
  final DateTime startTime;
  final String hostName;
  bool isStarted;

  // 每個會議有自己獨立的人員名單
  final List<User> users;

  List<VoteSession> voteHistory = [];
  VoteSession? currentVote;

  Meeting({
    required this.id,
    required this.title,
    required this.startTime,
    required this.hostName,
    required this.users,
    this.isStarted = false,
  });
}

// ---------------------------------------------------------------------------
// 2. 資料服務 (Data Service)
// ---------------------------------------------------------------------------

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // 儲存所有已建立的會議
  List<Meeting> meetings = [];

  // 當前選擇的會議
  Meeting? currentMeeting;

  // 取得當前會議的人員名單 (相容舊程式碼)
  List<User> get users => currentMeeting?.users ?? [];

  // 建立會議
  void createMeeting(String title, String hostName, List<User> initialUsers) {
    // 準備該會議的人員名單
    List<User> meetingUsers = [];

    // 自動加入主持人 (如果名單沒有)
    bool hostExists = initialUsers.any((u) => u.role == UserRole.host);
    if (!hostExists) {
      meetingUsers.add(User(
        id: 'host_${DateTime.now().millisecondsSinceEpoch}',
        name: hostName,
        role: UserRole.host,
        studentId: 'HOST',
        isSignedIn: true, // 主持人預設已到
        hasVotingRight: true,
      ));
    }
    meetingUsers.addAll(initialUsers);

    final newMeeting = Meeting(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      startTime: DateTime.now(),
      hostName: hostName,
      users: meetingUsers,
      isStarted: false,
    );

    meetings.add(newMeeting);
    currentMeeting = newMeeting; // 建立後預設選中
  }

  // 切換當前會議
  void selectMeeting(Meeting meeting) {
    currentMeeting = meeting;
  }

  // 執行簽到
  void signIn(String userId) {
    // 從當前會議名單中查找
    final user = users.firstWhere((u) => u.id == userId);
    user.isSignedIn = true;
  }

  // 執行清點人數 (賦予投票權)
  void performRollCall() {
    for (var user in users) {
      // 規則：只有「出席」身分且「已簽到」的人才能獲得投票權
      if (user.role == UserRole.attendee && user.isSignedIn) {
        user.hasVotingRight = true;
      }
    }
  }

  // 發起投票
  void startVote(String title, List<String> optionTexts, bool isAnonymous, int? duration) {
    if (currentMeeting == null) return;

    // 計算當下具投票權人數
    int eligibleCount = users.where((u) => u.hasVotingRight).length;

    List<VoteOption> options = optionTexts
        .map((text) => VoteOption(id: "${DateTime.now().microsecondsSinceEpoch}_$text", text: text))
        .toList();

    currentMeeting!.currentVote = VoteSession(
      id: DateTime.now().toString(),
      title: title,
      options: options,
      isAnonymous: isAnonymous,
      eligibleVotersCount: eligibleCount,
      durationSeconds: duration,
      startTime: DateTime.now(),
    );
  }

  // 投票動作
  void castVote(String userId, String optionId) {
    if (currentMeeting?.currentVote == null || !currentMeeting!.currentVote!.isActive) return;

    if (currentMeeting!.currentVote!.votedUserIds.contains(userId)) return;

    var option = currentMeeting!.currentVote!.options.firstWhere((o) => o.id == optionId);
    option.count++;

    currentMeeting!.currentVote!.votedUserIds.add(userId);

    // 紀錄記名投票
    if (!currentMeeting!.currentVote!.isAnonymous) {
      currentMeeting!.currentVote!.namedVotes[userId] = optionId;
    }
  }

  // 結束投票
  void endVote() {
    if (currentMeeting?.currentVote != null) {
      currentMeeting!.currentVote!.isActive = false;
      currentMeeting!.currentVote!.endTime = DateTime.now();
      currentMeeting!.voteHistory.add(currentMeeting!.currentVote!);
      currentMeeting!.currentVote = null;
    }
  }

  // 輔助：根據 ID 找人名
  String getUserName(String userId) {
    try {
      return users.firstWhere((u) => u.id == userId).name;
    } catch (e) {
      return "未知";
    }
  }
}

// ---------------------------------------------------------------------------
// 3. UI 介面
// ---------------------------------------------------------------------------

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '會議簽到投票系統',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

String _formatDate(DateTime dt) {
  return "${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
}

// 自定義 Radio Tile
class CustomRadioTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  const CustomRadioTile({
    super.key,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    return InkWell(
      onTap: enabled && onChanged != null ? () => onChanged!(value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: enabled ? (selected ? Colors.indigo : Colors.grey) : Colors.grey.shade300,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    fontSize: 16,
                    color: enabled ? Colors.black : Colors.grey,
                  )),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(
                      fontSize: 12,
                      color: enabled ? Colors.grey.shade700 : Colors.grey.shade300,
                    )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 畫面 1: 首頁
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
              Text("3. 投票選項：\n   主持人可動態新增投票選項，不限數量。"),
              SizedBox(height: 10),
              Text("4. 儀表板：\n   會議概況頁面包含即時簽到統計與詳細名單。"),
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

  // 修改：進入會議選擇列表
  void _handleJoinMeeting() {
    if (service.meetings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("目前沒有任何已建立的會議，請先建立！")));
      return;
    }
    // 跳轉到會議列表
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
            // 顯示當前系統內有多少會議
            if (service.meetings.isNotEmpty)
              Text("目前系統有 ${service.meetings.length} 場會議", style: const TextStyle(color: Colors.green)),
          ],
        ),
      ),
    );
  }
}

// 新增畫面：會議選擇列表
class MeetingSelectionScreen extends StatelessWidget {
  const MeetingSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DataService();

    return Scaffold(
      appBar: AppBar(title: const Text("選擇要參加的會議")),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: service.meetings.length,
        itemBuilder: (ctx, index) {
          final meeting = service.meetings[index];
          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.indigo),
              title: Text(meeting.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '主持人: ${meeting.hostName}\n時間: ${_formatDate(meeting.startTime)}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // 設定當前會議
                service.selectMeeting(meeting);
                // 進入身分選擇
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const RoleSelectionScreen())
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// 建立會議 Dialog
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
          role: _parseRole(parts[2]),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    label: const Text("下載範例", style: TextStyle(fontSize: 12)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade800,
                  ),
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
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                child: tempUsers.isEmpty
                    ? const Center(child: Text("尚未加入人員，請匯入檔案", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                  itemCount: tempUsers.length,
                  itemBuilder: (ctx, idx) {
                    final u = tempUsers[idx];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text("${u.name} (${u.studentId})"),
                      subtitle: Text(_getRoleText(u.role)),
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

// 畫面 2: 身分選擇
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final service = DataService();

  void _enterMeeting(User user) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => MeetingRoomScreen(currentUser: user)));
  }

  @override
  Widget build(BuildContext context) {
    final meeting = service.currentMeeting;
    if (meeting == null) return const Scaffold(body: Center(child: Text("無會議")));

    return Scaffold(
      appBar: AppBar(title: const Text('請選擇您的身分')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("會議：${meeting.title}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("主持人：${meeting.hostName}"),
                Text("時間：${_formatDate(meeting.startTime)}"),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("請從名單中點選您的名字進入", style: TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: service.users.isEmpty
                ? const Center(child: Text("名單為空，請由召集人新增"))
                : ListView.builder(
              itemCount: service.users.length,
              itemBuilder: (ctx, index) {
                final user = service.users[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getRoleColor(user.role),
                    child: Text(user.name.isNotEmpty ? user.name.substring(0, 1) : "?"),
                  ),
                  title: Text(user.name),
                  subtitle: Text("${_getRoleText(user.role)} ${user.studentId.isNotEmpty ? '(${user.studentId})' : ''}"),
                  trailing: user.isSignedIn
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.circle_outlined, color: Colors.grey),
                  onTap: () => _enterMeeting(user),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch(role) {
      case UserRole.host: return Colors.red;
      case UserRole.clerk: return Colors.orange;
      case UserRole.attendee: return Colors.blue;
      case UserRole.observer: return Colors.green;
    }
  }
}

// 畫面 3: 會議室主畫面
class MeetingRoomScreen extends StatefulWidget {
  final User currentUser;
  const MeetingRoomScreen({super.key, required this.currentUser});

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final service = DataService();
  Timer? _refreshTimer;
  String? _selectedOptionId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _handleSignIn() {
    setState(() {
      service.signIn(widget.currentUser.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("簽到成功！")));
  }

  @override
  Widget build(BuildContext context) {
    if (service.currentMeeting == null) {
      return Scaffold(appBar: AppBar(title: const Text("錯誤")), body: const Center(child: Text("會議不存在")));
    }

    final bool canControl = widget.currentUser.role == UserRole.host || widget.currentUser.role == UserRole.clerk;

    return Scaffold(
      appBar: AppBar(
        title: Text(service.currentMeeting!.title),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "會議概況"), Tab(text: "投票區")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(canControl),
          _buildVotingTab(canControl),
        ],
      ),
    );
  }

  Widget _buildInfoTab(bool canControl) {
    if (service.currentMeeting == null) return const SizedBox();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 個人狀態卡片
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text("你好，${widget.currentUser.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Chip(
                      label: Text(widget.currentUser.isSignedIn ? "已簽到" : "未簽到"),
                      backgroundColor: widget.currentUser.isSignedIn ? Colors.green.shade100 : Colors.red.shade100,
                    ),
                    Chip(
                      label: Text(widget.currentUser.hasVotingRight ? "有投票權" : "無投票權"),
                      backgroundColor: widget.currentUser.hasVotingRight ? Colors.green.shade100 : Colors.grey.shade300,
                    ),
                  ],
                ),
                if (!widget.currentUser.isSignedIn)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ElevatedButton(
                      onPressed: _handleSignIn,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      child: const Text("點此簽到"),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 2. 管理員控制區
        if (canControl) ...[
          const Text("管理員控制區", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ListTile(
            title: const Text("會議狀態切換"),
            subtitle: Text(service.currentMeeting!.isStarted ? "會議進行中" : "未開始"),
            trailing: Switch(
              value: service.currentMeeting!.isStarted,
              onChanged: (val) {
                setState(() {
                  service.currentMeeting!.isStarted = val;
                });
              },
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.people),
            label: const Text("執行「清點人數」 (更新投票權)"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                service.performRollCall();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("已清點人數！只有目前「已簽到」的「出席委員」獲得了投票權。"))
              );
            },
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.how_to_vote),
            label: const Text("發起新投票"),
            onPressed: _showCreateVoteDialog,
          ),
        ],

        const SizedBox(height: 20),

        // 3. 簽到儀表板與詳細名單
        _buildAttendanceDashboard(),
      ],
    );
  }

  // 簽到儀表板元件
  Widget _buildAttendanceDashboard() {
    final users = service.users;

    // 將使用者按身分分組
    Map<UserRole, List<User>> grouped = {};
    for (var r in UserRole.values) {
      grouped[r] = [];
    }
    for (var u in users) {
      grouped[u.role]?.add(u);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("簽到儀表板", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Divider(),

        // 統計卡片
        LayoutBuilder(builder: (context, constraints) {
          final double cardWidth = (constraints.maxWidth - 20) / 2; // 兩欄排列
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: UserRole.values.map((role) {
              final roleUsers = grouped[role]!;
              final total = roleUsers.length;
              final signed = roleUsers.where((u) => u.isSignedIn).length;

              return Container(
                width: cardWidth,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Text(_getRoleText(role), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    Text("$signed / $total", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text("已簽到 / 總數", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              );
            }).toList(),
          );
        }),

        const SizedBox(height: 20),
        const Text("詳細名單", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Divider(),

        // 詳細列表 (使用 ListView 顯示)
        if (users.isEmpty)
          const Text("尚無人員資料", style: TextStyle(color: Colors.grey)),

        ...users.map((u) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8)
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: u.isSignedIn ? Colors.green.shade100 : Colors.red.shade100,
                child: Icon(u.isSignedIn ? Icons.check : Icons.close, color: u.isSignedIn ? Colors.green : Colors.red, size: 16),
              ),
              title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${_getRoleText(u.role)} ${u.studentId.isNotEmpty ? '(${u.studentId})' : ''}"),
              trailing: u.hasVotingRight
                  ? const Chip(label: Text("有票"), backgroundColor: Colors.blueAccent, labelStyle: TextStyle(color: Colors.white, fontSize: 10))
                  : const Chip(label: Text("無票"), backgroundColor: Colors.grey, labelStyle: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVotingTab(bool canControl) {
    if (service.currentMeeting == null) return const SizedBox();

    final currentVote = service.currentMeeting!.currentVote;
    final history = service.currentMeeting!.voteHistory;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentVote != null && currentVote.isActive) ...[
            const Text("🔥 正在進行的投票", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
            _buildActiveVoteCard(currentVote, canControl),
          ] else
            const Center(child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("目前沒有進行中的投票"),
            )),

          const Divider(height: 40),

          const Text("📋 投票歷史紀錄", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...history.reversed.map((vote) => _buildResultCard(vote)).toList(),
        ],
      ),
    );
  }

  Widget _buildActiveVoteCard(VoteSession vote, bool canControl) {
    bool canVote = widget.currentUser.hasVotingRight && !vote.votedUserIds.contains(widget.currentUser.id);

    String timeLeft = "手動結束";
    if (vote.durationSeconds != null) {
      final now = DateTime.now();
      final end = vote.startTime!.add(Duration(seconds: vote.durationSeconds!));
      final diff = end.difference(now).inSeconds;
      if (diff <= 0) {
        if (vote.isActive) {
          Future.microtask(() => service.endVote());
        }
        timeLeft = "已結束";
      } else {
        timeLeft = "$diff 秒";
      }
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vote.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text("剩餘時間: $timeLeft", style: const TextStyle(color: Colors.red)),
            Text("具投票權人數: ${vote.eligibleVotersCount} 人", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),

            ...vote.options.map((option) {
              return CustomRadioTile<String>(
                title: option.text,
                value: option.id,
                groupValue: _selectedOptionId,
                onChanged: canVote ? (val) {
                  setState(() {
                    _selectedOptionId = val;
                  });
                  if (val != null) {
                    service.castVote(widget.currentUser.id, val);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("投票成功")));
                    setState(() { _selectedOptionId = null; });
                  }
                } : null,
                subtitle: canVote ? null : "無權限或已投票",
              );
            }),

            if (canControl)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: () {
                      service.endVote();
                      setState(() {});
                    },
                    child: const Text("結束投票 (公佈結果)"),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(VoteSession vote) {
    // 1. 計算基本數據
    int totalVotes = vote.options.fold(0, (sum, item) => sum + item.count);
    int eligibleCount = vote.eligibleVotersCount;

    // 2. 計算棄權 (具投票權人數 - 實際投票人數)
    // 若總票數 > 投票權人數(理論上不應發生，但做保護)，棄權為0
    int abstentionCount = (eligibleCount - totalVotes) < 0 ? 0 : (eligibleCount - totalVotes);

    double abstentionPercent = eligibleCount == 0 ? 0.0 : (abstentionCount / eligibleCount);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(vote.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                if (vote.isAnonymous)
                  const Chip(label: Text("不記名"), backgroundColor: Colors.grey, labelStyle: TextStyle(color: Colors.white, fontSize: 10))
                else
                  const Chip(label: Text("記名"), backgroundColor: Colors.blue, labelStyle: TextStyle(color: Colors.white, fontSize: 10))
              ],
            ),
            const SizedBox(height: 4),
            Text("投票權人數: $eligibleCount | 實投: $totalVotes | 棄權: $abstentionCount", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(),

            // 3. 顯示各選項結果
            ...vote.options.map((opt) {
              // 百分比分母改為「具投票權總人數」
              double percent = eligibleCount == 0 ? 0 : (opt.count / eligibleCount);

              // 抓取投給這個選項的人名 (僅限記名投票)
              List<String> votersName = [];
              if (!vote.isAnonymous) {
                vote.namedVotes.forEach((userId, optionId) {
                  if (optionId == opt.id) {
                    votersName.add(service.getUserName(userId));
                  }
                });
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(opt.text),
                        Text("${opt.count} 票 (${(percent * 100).toStringAsFixed(1)}%)"),
                      ],
                    ),
                    LinearProgressIndicator(value: percent, backgroundColor: Colors.grey.shade200),

                    // 記名投票：顯示名單
                    if (!vote.isAnonymous && votersName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                        child: Text(
                          "投票者: ${votersName.join(", ")}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              );
            }),

            // 4. 顯示棄權統計
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("棄權 (未投票)", style: TextStyle(color: Colors.red)),
                      Text("$abstentionCount 票 (${(abstentionPercent * 100).toStringAsFixed(1)}%)", style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                  LinearProgressIndicator(value: abstentionPercent, backgroundColor: Colors.grey.shade200, valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateVoteDialog() {
    final titleController = TextEditingController();
    final durationController = TextEditingController(text: "30");
    bool isAnonymous = false;

    List<TextEditingController> optionControllers = [
      TextEditingController(text: "同意"),
      TextEditingController(text: "不同意"),
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text("發起新投票"),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(controller: titleController, decoration: const InputDecoration(labelText: "投票主題", hintText: "例：第一案表決")),
                        TextField(controller: durationController, decoration: const InputDecoration(labelText: "時長(秒)，若空則為手動結束"), keyboardType: TextInputType.number),
                        CheckboxListTile(
                          title: const Text("是否記名 (顯示投票者)"),
                          subtitle: const Text("若取消勾選則為記名投票"),
                          value: isAnonymous,
                          onChanged: (val) => setState(() => isAnonymous = val!),
                        ),
                        const SizedBox(height: 10),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("投票選項", style: TextStyle(fontWeight: FontWeight.bold)),
                            TextButton.icon(
                              icon: const Icon(Icons.add_circle, size: 16),
                              label: const Text("新增選項"),
                              onPressed: () {
                                setState(() {
                                  optionControllers.add(TextEditingController());
                                });
                              },
                            )
                          ],
                        ),
                        ...List.generate(optionControllers.length, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: optionControllers[index],
                                    decoration: InputDecoration(
                                      labelText: "選項 ${index + 1}",
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                if (optionControllers.length > 2)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        optionControllers.removeAt(index);
                                      });
                                    },
                                  )
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
                  ElevatedButton(
                    onPressed: () {
                      List<String> validOptions = optionControllers
                          .map((c) => c.text.trim())
                          .where((t) => t.isNotEmpty)
                          .toList();

                      if (titleController.text.isNotEmpty && validOptions.length >= 2) {
                        service.startVote(
                          titleController.text,
                          validOptions,
                          isAnonymous,
                          int.tryParse(durationController.text),
                        );
                        Navigator.pop(ctx);
                        _tabController.animateTo(1);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("請輸入主題並至少提供兩個有效選項")));
                      }
                    },
                    child: const Text("發起"),
                  ),
                ],
              );
            }
        );
      },
    );
  }
}