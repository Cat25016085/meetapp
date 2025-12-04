// 定義使用者身分
enum UserRole {
  host,     // 主席
  clerk,    // 紀錄
  attendee, // 出席
  observer, // 列席
}

// 會議概況的顯示模式 (由紀錄控制)
enum PublicViewMode {
  agenda,     // 議程/預設畫面
  liveVotes,  // 即時投票結果
  dashboard,  // 簽到儀表板
}

// 輔助函式：文字轉身分
UserRole parseRole(String roleStr) {
  final cleanStr = roleStr.trim();
  if (cleanStr.contains('主') || cleanStr.contains('host')) return UserRole.host;
  if (cleanStr.contains('紀錄') || cleanStr.contains('clerk')) return UserRole.clerk;
  if (cleanStr.contains('旁') || cleanStr.contains('列') || cleanStr.contains('observer')) return UserRole.observer;
  return UserRole.attendee; // 預設為出席
}

// 輔助函式：身分轉文字
String getRoleText(UserRole role) {
  switch(role) {
    case UserRole.host: return "主席";
    case UserRole.clerk: return "紀錄";
    case UserRole.attendee: return "出席";
    case UserRole.observer: return "列席";
  }
}

// 使用者模型
class User {
  final String id;
  final String name;
  final UserRole role;
  String studentId;

  bool isSignedIn;      // 是否簽到
  bool hasVotingRight;  // 是否有投票權

  User({
    required this.id,
    required this.name,
    required this.role,
    this.studentId = '',
    this.isSignedIn = false,
    this.hasVotingRight = false,
  });
}

// 投票選項模型
class VoteOption {
  final String id;
  final String text;
  int count;

  VoteOption({required this.id, required this.text, this.count = 0});
}

// 單次投票場次模型
class VoteSession {
  final String id;
  final String title;
  final List<VoteOption> options;
  final bool isAnonymous;
  final int? durationSeconds;

  // 紀錄投票結束當下具投票權的總人數 (分母)
  // 若還沒結束，此值暫存為發起時的人數，但在結束時會更新
  int eligibleVotersCount;

  // 需迴避的人員 ID 列表 (這些人在此案無投票權)
  final Set<String> excludedUserIds;

  bool isActive;
  DateTime? startTime;
  DateTime? endTime;

  Set<String> votedUserIds = {}; // 已投票的人 ID
  Map<String, String> namedVotes = {}; // 記名投票紀錄 <UserId, OptionId>

  VoteSession({
    required this.id,
    required this.title,
    required this.options,
    required this.isAnonymous,
    required this.eligibleVotersCount,
    this.excludedUserIds = const {},
    this.durationSeconds,
    this.isActive = true,
    this.startTime,
  });
}

// 會議模型
class Meeting {
  final String id;
  final String title;
  final DateTime startTime;
  final String hostName;
  bool isStarted;

  // 當前會議概況要顯示什麼 (由紀錄控制)
  PublicViewMode currentViewMode;

  final List<User> users; // 該會議的人員名單
  List<VoteSession> voteHistory = [];

  // 支援多個進行中的投票
  List<VoteSession> activeVotes = [];

  Meeting({
    required this.id,
    required this.title,
    required this.startTime,
    required this.hostName,
    required this.users,
    this.isStarted = false,
    this.currentViewMode = PublicViewMode.agenda,
  });
}