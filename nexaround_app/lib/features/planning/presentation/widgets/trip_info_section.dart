import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

/// Practical Information, Booking Plan, and Sources — the parts of the
/// generated Odyssey that don't belong on Overview (already dense) or
/// Itinerary (day-by-day only). Renders only what the backend actually sent;
/// legacy Odysseys generated before these fields existed show nothing here.
class TripInfoSection extends StatelessWidget {
  final Odyssey odyssey;

  const TripInfoSection({super.key, required this.odyssey});

  static const List<String> _labelOrder = [
    'BOOK NOW',
    'BOOK AFTER VISA',
    'BOOK CLOSER TO TRAVEL',
    'CAN WAIT',
  ];

  @override
  Widget build(BuildContext context) {
    final info = odyssey.practicalInfo;
    final hasInfo = !info.isEmpty;
    final hasBookingPlan = odyssey.bookingPlan.isNotEmpty;
    final hasSources = odyssey.verifiedSources.isNotEmpty;

    if (!hasInfo && !hasBookingPlan && !hasSources) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasInfo) ...[
          _sectionHeader(
            Icons.info_outline_rounded,
            'PRACTICAL INFORMATION',
            'Money, Connectivity, Safety & Customs',
          ),
          const SizedBox(height: 16),
          _practicalInfoCard(info),
          const SizedBox(height: 24),
        ],
        if (hasBookingPlan) ...[
          _sectionHeader(
            Icons.checklist_rounded,
            'BOOKING PLAN',
            'What to Book, and When',
          ),
          const SizedBox(height: 16),
          _bookingPlanCard(context),
          const SizedBox(height: 24),
        ],
        if (hasSources) ...[
          _sectionHeader(
            Icons.verified_rounded,
            'SOURCES',
            'Verified via Google Search',
          ),
          const SizedBox(height: 16),
          _sourcesCard(context),
        ],
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String eyebrow, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.black87, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _practicalInfoCard(OdysseyPracticalInfo info) {
    final rows = <MapEntry<String, String>>[
      if (info.money.isNotEmpty) MapEntry('Money', info.money),
      if (info.connectivity.isNotEmpty) MapEntry('Connectivity', info.connectivity),
      if (info.safety.isNotEmpty) MapEntry('Safety', info.safety),
      if (info.customs.isNotEmpty) MapEntry('Customs', info.customs),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: Colors.black12),
              ),
            Text(
              rows[i].key.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rows[i].value,
              style: const TextStyle(fontSize: 14, height: 1.45, color: Colors.black87),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bookingPlanCard(BuildContext context) {
    final grouped = <String, List<OdysseyBookingPlanItem>>{};
    for (final item in odyssey.bookingPlan) {
      grouped.putIfAbsent(item.label, () => []).add(item);
    }
    final orderedLabels = [
      ..._labelOrder.where(grouped.containsKey),
      ...grouped.keys.where((l) => !_labelOrder.contains(l)),
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var li = 0; li < orderedLabels.length; li++) ...[
            if (li > 0) const SizedBox(height: 16),
            _labelChip(orderedLabels[li]),
            const SizedBox(height: 8),
            for (final item in grouped[orderedLabels[li]]!) _bookingPlanRow(context, item),
          ],
        ],
      ),
    );
  }

  Widget _labelChip(String label) {
    Color color;
    switch (label) {
      case 'BOOK NOW':
        color = AppColors.error;
      case 'BOOK AFTER VISA':
        color = AppColors.warning;
      case 'BOOK CLOSER TO TRAVEL':
        color = AppColors.brandGreen;
      default:
        color = Colors.black54;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }

  Widget _bookingPlanRow(BuildContext context, OdysseyBookingPlanItem item) {
    final hasUrl = item.url.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: hasUrl ? () => _launch(context, item.url) : null,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Icon(Icons.circle, size: 6, color: Colors.black45),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.item,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  if (item.reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.reason,
                      style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            if (hasUrl)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.open_in_new_rounded, size: 15, color: Colors.black38),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sourcesCard(BuildContext context) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: odyssey.verifiedSources.map((s) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => _launch(context, s.uri),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.link_rounded, size: 15, color: AppColors.brandGreen),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.title.isNotEmpty ? s.title : s.uri,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandGreen,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    try {
      final uri = Uri.parse(trimmed);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $trimmed')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }
}
