import '../models/meeting_models.dart';

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  List<Meeting> meetings = [];
  Meeting? currentMeeting;

  List<User> get users => currentMeeting?.users ?? [];

  void createMeeting(String title, String hostName, List<User> initialUsers) {
    List<User> meetingUsers = [];
    bool hostExists = initialUsers.any((u) => u.role == UserRole.host);
    if (!hostExists) {
      meetingUsers.add(User(
        id: 'host_${DateTime.now().millisecondsSinceEpoch}',
        name: hostName,
        role: UserRole.host,
        studentId: 'HOST',
        isSignedIn: true,
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
    );

    meetings.add(newMeeting);
    currentMeeting = newMeeting;
  }

  void selectMeeting(Meeting meeting) {
    currentMeeting = meeting;
  }

  void signIn(String userId) {
    try {
      final user = users.firstWhere((u) => u.id == userId);
      user.isSignedIn = true;
    } catch (_) {}
  }

  // 紀錄控制顯示模式
  void setPublicViewMode(PublicViewMode mode) {
    if (currentMeeting != null) {
      currentMeeting!.currentViewMode = mode;
    }
  }

  void performRollCall() {
    for (var user in users) {
      if (user.role == UserRole.attendee && user.isSignedIn) {
        user.hasVotingRight = true;
      }
    }
  }

  // 發起投票 (支援迴避名單)
  void startVote(String title, List<String> optionTexts, bool isAnonymous, int? duration, Set<String> excludedIds) {
    if (currentMeeting == null) return;

    // 計算初始分母 (僅供參考，結束時會更新)
    // 具投票權 - 迴避人員
    int eligibleCount = users.where((u) => u.hasVotingRight && !excludedIds.contains(u.id)).length;

    List<VoteOption> options = optionTexts
        .map((text) => VoteOption(id: "${DateTime.now().microsecondsSinceEpoch}_$text", text: text))
        .toList();

    final newVote = VoteSession(
      id: DateTime.now().toString(),
      title: title,
      options: options,
      isAnonymous: isAnonymous,
      eligibleVotersCount: eligibleCount,
      excludedUserIds: excludedIds,
      durationSeconds: duration,
      startTime: DateTime.now(),
    );

    currentMeeting!.activeVotes.add(newVote);
  }

  // 投票動作 (增加迴避檢查)
  // 回傳 true 代表成功，false 代表失敗(無權/迴避/已投)
  bool castVote(String voteId, String userId, String optionId) {
    if (currentMeeting == null) return false;

    // 找到對應的投票場次
    try {
      final voteSession = currentMeeting!.activeVotes.firstWhere((v) => v.id == voteId);

      if (!voteSession.isActive) return false;
      if (voteSession.votedUserIds.contains(userId)) return false;

      // 檢查是否被迴避
      if (voteSession.excludedUserIds.contains(userId)) return false;

      // 檢查是否有基本投票權
      final user = users.firstWhere((u) => u.id == userId);
      if (!user.hasVotingRight) return false;

      var option = voteSession.options.firstWhere((o) => o.id == optionId);
      option.count++;

      voteSession.votedUserIds.add(userId);

      if (!voteSession.isAnonymous) {
        voteSession.namedVotes[userId] = optionId;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // 結束投票
  void endVote(String voteId) {
    if (currentMeeting == null) return;

    try {
      final voteSession = currentMeeting!.activeVotes.firstWhere((v) => v.id == voteId);
      voteSession.isActive = false;
      voteSession.endTime = DateTime.now();

      // 關鍵更新：以「結束當下」的狀態更新分母
      // 分母 = 當下有投票權的人數 - 此案迴避的人數
      int currentEligible = users.where((u) => u.hasVotingRight && !voteSession.excludedUserIds.contains(u.id)).length;
      voteSession.eligibleVotersCount = currentEligible;

      currentMeeting!.voteHistory.add(voteSession);
      currentMeeting!.activeVotes.removeWhere((v) => v.id == voteId);
    } catch (_) {}
  }

  String getUserName(String userId) {
    try {
      return users.firstWhere((u) => u.id == userId).name;
    } catch (e) {
      return "未知";
    }
  }
}