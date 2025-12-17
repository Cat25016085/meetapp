import 'dart:async';
import 'package:flutter/material.dart';
import '../services/data_service.dart';
import '../models/meeting_models.dart';
import '../widgets/custom_radio_tile.dart';
import '../main.dart';
import 'dashboard_screen.dart';

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

  final Map<String, String> _selectedOptions = {};

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
        actions: [
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "會議概況"), Tab(text: "投票區")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(canControl),
          _buildVotingTab(canControl),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(bool canControl) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("你好，${widget.currentUser.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (widget.currentUser.isSignedIn)
                const Chip(label: Text("已簽到"), backgroundColor: Colors.green, labelStyle: TextStyle(color: Colors.white))
              else
                ElevatedButton.icon(
                  onPressed: _handleSignIn,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text("點此簽到"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                )
            ],
          ),
        ),

        if (canControl)
          ExpansionTile(
            title: const Text("🔧 紀錄控制台 (切換全體顯示畫面)"),
            backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black12 : Colors.orange.shade50,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text("顯示議程"),
                    onPressed: () => setState(() => service.setPublicViewMode(PublicViewMode.agenda)),
                    backgroundColor: service.currentMeeting!.currentViewMode == PublicViewMode.agenda ? Colors.orange : null,
                  ),
                  ActionChip(
                    label: const Text("顯示即時票況"),
                    onPressed: () => setState(() => service.setPublicViewMode(PublicViewMode.liveVotes)),
                    backgroundColor: service.currentMeeting!.currentViewMode == PublicViewMode.liveVotes ? Colors.orange : null,
                  ),
                  ActionChip(
                    label: const Text("顯示簽到儀表板"),
                    onPressed: () => setState(() => service.setPublicViewMode(PublicViewMode.dashboard)),
                    backgroundColor: service.currentMeeting!.currentViewMode == PublicViewMode.dashboard ? Colors.orange : null,
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() => service.performRollCall());
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已更新全體投票權！")));
                    },
                    child: const Text("執行清點人數"),
                  ),
                  ElevatedButton(
                    onPressed: _showCreateVoteDialog,
                    child: const Text("發起新投票"),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),

        Expanded(
          child: _buildPublicDisplayContent(),
        ),
      ],
    );
  }

  Widget _buildPublicDisplayContent() {
    switch (service.currentMeeting!.currentViewMode) {
      case PublicViewMode.dashboard:
        return const DashboardScreen(isEmbedded: true);

      case PublicViewMode.liveVotes:
        if (service.currentMeeting!.activeVotes.isEmpty) {
          return const Center(child: Text("目前沒有進行中的投票"));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: service.currentMeeting!.activeVotes.map((vote) {
            int eligible = service.users.where((u) => u.hasVotingRight && !vote.excludedUserIds.contains(u.id)).length;
            int voted = vote.votedUserIds.length;
            int remaining = eligible - voted;
            if (remaining < 0) remaining = 0;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text("進行中：${vote.title}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 10),
                    Text("已投: $voted  |  未投: $remaining", style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: eligible == 0 ? 0 : voted / eligible),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case PublicViewMode.agenda:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.event_note, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              Text("會議進行中...", style: TextStyle(fontSize: 24, color: Colors.grey[600])),
              const SizedBox(height: 10),
              const Text("請等待主席指示或切換至投票區"),
            ],
          ),
        );
    }
  }

  Widget _buildVotingTab(bool canControl) {
    if (service.currentMeeting == null) return const SizedBox();

    final activeVotes = service.currentMeeting!.activeVotes;
    final history = service.currentMeeting!.voteHistory;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activeVotes.isNotEmpty) ...[
            const Text("🔥 正在進行的投票", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
            ...activeVotes.map((vote) => _buildActiveVoteCard(vote, canControl)),
          ] else
            const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("目前沒有進行中的投票"))),

          const Divider(height: 40),
          const Text("📋 投票歷史紀錄", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...history.reversed.map((vote) => _buildResultCard(vote, isHistory: true)),
        ],
      ),
    );
  }

  Widget _buildActiveVoteCard(VoteSession vote, bool canControl) {
    bool hasRight = widget.currentUser.hasVotingRight && !vote.excludedUserIds.contains(widget.currentUser.id);
    bool hasVoted = vote.votedUserIds.contains(widget.currentUser.id);

    String timeLeft = "手動結束";
    if (vote.durationSeconds != null && vote.isActive) {
      final end = vote.startTime!.add(Duration(seconds: vote.durationSeconds!));
      final diff = end.difference(DateTime.now()).inSeconds;
      if (diff <= 0) {
        Future.microtask(() => service.endVote(vote.id));
        timeLeft = "已結束";
      } else {
        timeLeft = "$diff 秒";
      }
    }

    Widget content;
    if (hasVoted) {
      content = Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 40),
          const Text("您已完成投票，等待結果中...", style: TextStyle(color: Colors.green)),
          const Divider(),
          _buildResultCard(vote, isHistory: false),
        ],
      );
    } else if (!hasRight) {
      content = Column(
        children: [
          const Icon(Icons.block, color: Colors.grey, size: 40),
          Text(vote.excludedUserIds.contains(widget.currentUser.id) ? "您需迴避此案" : "您目前無投票權", style: const TextStyle(color: Colors.grey)),
        ],
      );
    } else {
      content = Column(
        children: [
          ...vote.options.map((option) {
            return CustomRadioTile<String>(
              title: option.text,
              value: option.id,
              groupValue: _selectedOptions[vote.id],
              onChanged: (val) {
                setState(() => _selectedOptions[vote.id] = val!);
              },
            );
          }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedOptions[vote.id] == null ? null : () => _confirmVote(vote, _selectedOptions[vote.id]!),
              child: const Text("確認投票"),
            ),
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.redAccent, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(vote.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                Text(timeLeft, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            if (vote.excludedUserIds.isNotEmpty)
              Text("迴避人數: ${vote.excludedUserIds.length} 人", style: const TextStyle(fontSize: 12, color: Colors.orange)),
            const Divider(),
            content,
            if (canControl)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: () {
                      service.endVote(vote.id);
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

  void _confirmVote(VoteSession vote, String optionId) {
    String optionText = vote.options.firstWhere((o) => o.id == optionId).text;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("確認投票"),
        content: Text("您選擇了：「$optionText」\n\n送出後將無法更改，確定嗎？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              bool success = service.castVote(vote.id, widget.currentUser.id, optionId);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("投票成功")));
                setState(() {});
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("投票失敗")));
              }
            },
            child: const Text("確定送出"),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(VoteSession vote, {required bool isHistory}) {
    int eligibleCount;
    if (isHistory) {
      eligibleCount = vote.eligibleVotersCount;
    } else {
      eligibleCount = service.users.where((u) => u.hasVotingRight && !vote.excludedUserIds.contains(u.id)).length;
    }

    int totalVotes = vote.options.fold(0, (sum, item) => sum + item.count);
    int abstentionCount = (eligibleCount - totalVotes) < 0 ? 0 : (eligibleCount - totalVotes);
    double abstentionPercent = eligibleCount == 0 ? 0.0 : (abstentionCount / eligibleCount);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: isHistory ? null : Colors.grey.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isHistory)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(vote.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  Chip(
                      label: Text(vote.isAnonymous ? "不記名" : "記名"),
                      backgroundColor: vote.isAnonymous ? Colors.grey : Colors.blue,
                      labelStyle: const TextStyle(color: Colors.white, fontSize: 10)
                  )
                ],
              ),
            Text("應投: $eligibleCount | 實投: $totalVotes | 棄權: $abstentionCount", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),

            ...vote.options.map((opt) {
              double percent = eligibleCount == 0 ? 0 : (opt.count / eligibleCount);
              List<String> votersName = [];
              if (!vote.isAnonymous) {
                vote.namedVotes.forEach((userId, optionId) {
                  if (optionId == opt.id) votersName.add(service.getUserName(userId));
                });
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(opt.text), Text("${opt.count} 票 (${(percent * 100).toStringAsFixed(1)}%)")],
                    ),
                    LinearProgressIndicator(value: percent, backgroundColor: Colors.grey.withValues(alpha: 0.3)),
                    if (!vote.isAnonymous && votersName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                        child: Text("投票者: ${votersName.join(", ")}", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ),
                  ],
                ),
              );
            }),

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
                  LinearProgressIndicator(value: abstentionPercent, backgroundColor: Colors.grey.withValues(alpha: 0.3), valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent)),
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
    List<TextEditingController> optionControllers = [TextEditingController(text: "同意"), TextEditingController(text: "不同意")];
    Set<String> tempExcludedIds = {};

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("發起新投票"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: titleController, decoration: const InputDecoration(labelText: "投票主題")),
                    TextField(controller: durationController, decoration: const InputDecoration(labelText: "時長(秒)"), keyboardType: TextInputType.number),

                    CheckboxListTile(
                      title: const Text("不記名投票"),
                      subtitle: const Text("預設為記名投票，勾選則為不記名"),
                      value: isAnonymous, onChanged: (val) => setState(() => isAnonymous = val!),
                    ),
                    const Divider(),

                    ExpansionTile(
                      title: Text("設定迴避人員 (${tempExcludedIds.length})"),
                      children: service.users.where((u) => u.hasVotingRight).map((u) {
                        return CheckboxListTile(
                          title: Text(u.name),
                          subtitle: Text(u.studentId),
                          value: tempExcludedIds.contains(u.id),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                tempExcludedIds.add(u.id);
                              } else {
                                tempExcludedIds.remove(u.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const Divider(),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("投票選項", style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          icon: const Icon(Icons.add_circle, size: 16), label: const Text("新增選項"),
                          onPressed: () => setState(() => optionControllers.add(TextEditingController())),
                        )
                      ],
                    ),
                    ...List.generate(optionControllers.length, (index) {
                      return Row(children: [
                        Expanded(child: TextField(controller: optionControllers[index], decoration: InputDecoration(labelText: "選項 ${index + 1}", isDense: true))),
                        if (optionControllers.length > 2) IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setState(() => optionControllers.removeAt(index)))
                      ]);
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
              ElevatedButton(
                onPressed: () {
                  List<String> validOptions = optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                  if (titleController.text.isNotEmpty && validOptions.length >= 2) {
                    service.startVote(
                        titleController.text,
                        validOptions,
                        isAnonymous,
                        int.tryParse(durationController.text),
                        tempExcludedIds
                    );
                    Navigator.pop(ctx);
                    _tabController.animateTo(1);
                  }
                },
                child: const Text("發起"),
              ),
            ],
          );
        });
      },
    );
  }
}