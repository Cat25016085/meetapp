import 'package:flutter/material.dart';
import '../models/meeting_models.dart';
import '../services/data_service.dart';

class DashboardScreen extends StatelessWidget {
  final bool isEmbedded; // 是否嵌入在 Tab 頁面中 (如果 false 則顯示 Scaffold)

  const DashboardScreen({super.key, this.isEmbedded = false});

  @override
  Widget build(BuildContext context) {
    final service = DataService();
    final users = service.users;

    // 統計
    Map<UserRole, List<User>> grouped = {};
    for (var r in UserRole.values) {
      grouped[r] = [];
    }
    for (var u in users) {
      grouped[u.role]?.add(u);
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("📊 簽到統計儀表板", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          final double cardWidth = (constraints.maxWidth - 20) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: UserRole.values.map((role) {
              final roleUsers = grouped[role]!;
              final total = roleUsers.length;
              final signed = roleUsers.where((u) => u.isSignedIn).length;

              return Container(
                width: cardWidth,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    Text(getRoleText(role), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text("$signed / $total", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text("已簽到 / 總數", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            }).toList(),
          );
        }),

        const SizedBox(height: 30),
        const Text("📋 詳細人員名單", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const Divider(),

        if (users.isEmpty)
          const Text("尚無人員資料", style: TextStyle(color: Colors.grey)),

        ...users.map((u) {
          // 修正：使用 withValues(alpha: ...) 取代 withOpacity
          final checkColor = u.isSignedIn ? Colors.green : Colors.red;
          final avatarBg = u.isSignedIn
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.red.withValues(alpha: 0.2);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)), // 修正 opacity
                borderRadius: BorderRadius.circular(8)
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: avatarBg,
                child: Icon(u.isSignedIn ? Icons.check : Icons.close, color: checkColor, size: 16),
              ),
              title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${getRoleText(u.role)} ${u.studentId.isNotEmpty ? '(${u.studentId})' : ''}"),
              trailing: u.hasVotingRight
                  ? const Chip(label: Text("有票"), backgroundColor: Colors.blueAccent, labelStyle: TextStyle(color: Colors.white, fontSize: 10))
                  : const Chip(label: Text("無票"), backgroundColor: Colors.grey, labelStyle: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          );
        }),
      ],
    );

    if (isEmbedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text("簽到儀表板")),
      body: content,
    );
  }
}