import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// ✅ SQUARE DASHBOARD CARD
class DashboardCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const DashboardCard(
      {super.key,
      required this.title,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: color, size: 24)),
                  const SizedBox(height: 10),
                  Text(title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textDark))
                ])),
      ),
    );
  }
}

// ✅ WIDE DASHBOARD CARD (LIST STYLE)
class DashboardWideCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const DashboardWideCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
            onTap: onTap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: Colors.grey[600])),
            title: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: textDark)),
            subtitle: Text(subtitle,
                style: const TextStyle(fontSize: 12, color: textGrey)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey)));
  }
}
