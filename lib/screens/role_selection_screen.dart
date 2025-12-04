import 'dart:async';
import 'package:flutter/material.dart';
import '../services/data_service.dart';
import '../models/meeting_models.dart';
import 'meeting_room_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final service = DataService();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // 1. 定時刷新，確保簽到狀態(勾勾)即時顯示
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _enterMeeting(User user) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => MeetingRoomScreen(currentUser: user)));
  }

  String _formatDate(DateTime dt) {
    return "${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
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
            color: Theme.of(context).cardTheme.color,
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
                ? const Center(child: Text("名單為空"))
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
                  subtitle: Text("${getRoleText(user.role)} ${user.studentId.isNotEmpty ? '(${user.studentId})' : ''}"),
                  trailing: user.isSignedIn
                      ? const Icon(Icons.check_circle, color: Colors.green) // 1. 已簽到顯示綠勾
                      : Icon(Icons.circle_outlined, color: Colors.grey.shade400),
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