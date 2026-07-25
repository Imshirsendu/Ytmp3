import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/server_provider.dart';

class ServerStatusBadge extends StatelessWidget {
  const ServerStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerProvider>();
    final tt = Theme.of(context).textTheme;

    final (label, color) = switch (server.status) {
      ServerStatus.online   => ('Online',   Colors.green),
      ServerStatus.offline  => ('Offline',  Colors.red),
      ServerStatus.checking => ('Checking', Colors.orange),
      ServerStatus.unknown  => ('Unknown',  Colors.grey),
    };

    return GestureDetector(
      onTap: server.checkNow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: tt.labelSmall?.copyWith(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
