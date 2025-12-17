import 'package:flutter/material.dart';
import '../services/data_service.dart';
import 'role_selection_screen.dart';

class MeetingSelectionScreen extends StatelessWidget {
  const MeetingSelectionScreen({super.key});

  String _formatDate(DateTime dt) {
    return "${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

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
                service.selectMeeting(meeting);
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