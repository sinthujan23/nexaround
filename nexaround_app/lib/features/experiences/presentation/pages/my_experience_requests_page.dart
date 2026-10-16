import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/contact_launcher.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_request.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_link_page.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_terms_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_review_sheet.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_stars.dart';

/// Opens My requests; with [openRequestId] (a notification tap), that
/// request's details open on top once the list has loaded.
Future<void> showMyExperienceRequests(
  BuildContext context, {
  String? openRequestId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MyExperienceRequestsPage(openRequestId: openRequestId),
    ),
  );
}

/// The traveller's experience requests: where each one stands, how to reach
/// the provider, and the only in-app way to cancel (which is what makes the
/// 72-hour rule checkable: the server stamps the time).
class MyExperienceRequestsPage extends StatefulWidget {
  final String? openRequestId;

  const MyExperienceRequestsPage({super.key, this.openRequestId});

  @override
  State<MyExperienceRequestsPage> createState() =>
      _MyExperienceRequestsPageState();
}

class _MyExperienceRequestsPageState extends State<MyExperienceRequestsPage> {
  List<ExperienceRequest>? _requests = ExperiencesService.cachedMyRequests();
  bool _loading = true;
  bool _failed = false;
  late String? _pendingOpen = widget.openRequestId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final fresh = await ExperiencesService.fetchMyRequests();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _requests = fresh;
      _failed = fresh == null;
      _loading = false;
    });
    _openPending();
  }

  void _openPending() {
    final id = _pendingOpen;
    final requests = _requests;
    if (id == null || requests == null) return;
    _pendingOpen = null;
    for (final request in requests) {
      if (request.id == id) {
        _open(request);
        return;
      }
    }
  }

  void _replace(ExperienceRequest updated) {
    setState(() {
      _requests = [
        for (final r in _requests ?? const <ExperienceRequest>[])
          r.id == updated.id ? updated : r,
      ];
    });
  }

  Future<void> _open(ExperienceRequest request) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExperienceRequestSheet(
        request: request,
        onChanged: _replace,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My requests',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final requests = _requests;
    if (requests == null) {
      if (_loading) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brandGreen),
        );
      }
      return _message(
        Icons.cloud_off_rounded,
        "Couldn't load your requests",
        'Check your connection and try again.',
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            _message(
              Icons.receipt_long_rounded,
              'No requests yet',
              'When you request an experience, you can follow it and cancel it here.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: requests.length + (_failed ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (_failed && index == 0) {
            return const Text(
              "Showing saved requests. Pull down to refresh.",
              style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
            );
          }
          final request = requests[index - (_failed ? 1 : 0)];
          return _RequestCard(request: request, onTap: () => _open(request));
        },
      ),
    );
  }

  Widget _message(IconData icon, String title, String body, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textSecondary, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      ),
    );
  }
}

// ── Shared wording ────────────────────────────────────────────────────────────

String requestStatusLabel(String status) {
  switch (status) {
    case ExperienceRequest.statusNew:
      return 'Waiting for reply';
    case ExperienceRequest.statusContacted:
      return 'In touch';
    case ExperienceRequest.statusConfirmed:
      return 'Confirmed';
    case ExperienceRequest.statusClosed:
      return 'Closed';
    case ExperienceRequest.statusCustomerCancelled:
      return 'Cancelled by you';
    case ExperienceRequest.statusProviderCancelled:
      return 'Cancelled by provider';
    default:
      return status;
  }
}

Color requestStatusColor(String status) {
  switch (status) {
    case ExperienceRequest.statusNew:
      return const Color(0xFFB7791F);
    case ExperienceRequest.statusContacted:
      return const Color(0xFF1E6FD9);
    case ExperienceRequest.statusConfirmed:
      return AppColors.brandGreen;
    case ExperienceRequest.statusCustomerCancelled:
    case ExperienceRequest.statusProviderCancelled:
      return AppColors.error;
    default:
      return AppColors.textTertiary;
  }
}

String _day(BuildContext context, DateTime? value) => value == null
    ? ''
    : MaterialLocalizations.of(context).formatMediumDate(value);

String _guests(int? n) => n == null ? '' : '$n ${n == 1 ? 'guest' : 'guests'}';

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = requestStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        requestStatusLabel(status),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ExperienceRequest request;
  final VoidCallback onTap;

  const _RequestCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = PlaceImageHelper.resolveUrl(request.coverPhotoUrl);
    final date = request.bookedDate;
    final when = date == null
        ? 'Flexible date'
        : '${request.isConfirmed ? 'On' : 'Preferred'} ${_day(context, date)}';
    final details = [when, _guests(request.partySize)]
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: url == null
                      ? Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.kayaking_rounded,
                              color: AppColors.textTertiary),
                        )
                      : CachedNetworkImage(
                          imageUrl: url,
                          httpHeaders: PlaceImageHelper.headersFor(url),
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          errorWidget: (_, __, ___) =>
                              Container(color: AppColors.surface),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.packageTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (request.vendorName != null)
                      Text(
                        request.vendorName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      details,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: request.status),
            ],
          ),
        ),
      ),
    );
  }
}

/// One request: where it stands, what was asked, and what the traveller can
/// do about it (contact the provider, open the experience, cancel).
class ExperienceRequestSheet extends StatefulWidget {
  final ExperienceRequest request;
  final ValueChanged<ExperienceRequest> onChanged;

  const ExperienceRequestSheet({
    super.key,
    required this.request,
    required this.onChanged,
  });

  @override
  State<ExperienceRequestSheet> createState() => _ExperienceRequestSheetState();
}

class _ExperienceRequestSheetState extends State<ExperienceRequestSheet> {
  late ExperienceRequest _request = widget.request;
  bool _cancelling = false;

  Future<void> _review() async {
    final updated = await showExperienceReviewSheet(context, _request);
    if (updated == null || !mounted) return;
    setState(() => _request = updated);
    widget.onChanged(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thank you. Your review is saved.')),
    );
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(request: _request),
    );
    if (reason == null || !mounted) return; // kept the request

    setState(() => _cancelling = true);
    final result =
        await ExperiencesService.cancelRequest(_request.id, reason: reason);
    if (!mounted) return;
    setState(() => _cancelling = false);

    final updated = result.request;
    if (updated != null) {
      setState(() => _request = updated);
      widget.onChanged(updated);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.error ?? 'Your request has been cancelled.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      r.packageTitle,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: r.status),
                ],
              ),
              if (r.vendorName != null) ...[
                const SizedBox(height: 2),
                Text(r.vendorName!,
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 16),
              _statusBanner(context, r),
              const SizedBox(height: 16),
              _row(context, Icons.event_rounded,
                  r.isConfirmed ? 'Date' : 'Preferred date',
                  r.bookedDate == null ? 'Flexible' : _day(context, r.bookedDate)),
              if (r.partySize != null)
                _row(context, Icons.group_rounded, 'Guests', _guests(r.partySize)),
              if (r.pickupLocation != null)
                _row(context, Icons.place_rounded, 'Pickup', r.pickupLocation!),
              if (r.message != null)
                _row(context, Icons.notes_rounded, 'Your message', r.message!),
              if (r.createdAt != null)
                _row(context, Icons.schedule_rounded, 'Sent',
                    _day(context, r.createdAt)),
              if (r.canReview) ...[
                const SizedBox(height: 12),
                _reviewCard(r),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (r.vendorWhatsapp != null)
                    OutlinedButton.icon(
                      onPressed: () => ContactLauncher.whatsApp(
                        r.vendorWhatsapp,
                        message: 'Hi, about my request for "${r.packageTitle}" '
                            'on NexAround.',
                      ),
                      icon: const Icon(Icons.chat_rounded, size: 17),
                      label: const Text('WhatsApp'),
                    ),
                  if (r.vendorPhone != null)
                    OutlinedButton.icon(
                      onPressed: () => ContactLauncher.call(r.vendorPhone),
                      icon: const Icon(Icons.call_rounded, size: 17),
                      label: const Text('Call'),
                    ),
                  if (r.packageId != null)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ExperienceLinkPage(packageId: r.packageId!),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      label: const Text('View experience'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showExperienceTerms(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandGreen,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('Experience Booking Terms'),
              ),
              if (r.canCancel) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _cancelling ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _cancelling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.error),
                          )
                        : Text(r.isConfirmed ? 'Cancel booking' : 'Cancel request',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Rate the booking, or show the rating already given with a way to change it.
  Widget _reviewCard(ExperienceRequest r) {
    final review = r.review;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (review == null) ...[
            const Text('How was it?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text(
              'Rate this experience to help other travellers.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ] else ...[
            Row(
              children: [
                const Text('Your review',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                ExperienceStars(value: review.rating.toDouble(), size: 16),
              ],
            ),
            if (review.isHidden) ...[
              const SizedBox(height: 4),
              const Text(
                'This review was hidden by NexAround and is not shown to '
                'other travellers.',
                style: TextStyle(fontSize: 12.5, color: AppColors.error),
              ),
            ],
            if (review.comment != null) ...[
              const SizedBox(height: 6),
              Text(review.comment!,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
            if (review.vendorReply != null) ...[
              const SizedBox(height: 8),
              Text('Provider reply: ${review.vendorReply!}',
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary)),
            ],
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _review,
            icon: Icon(
                review == null ? Icons.star_rounded : Icons.edit_rounded,
                size: 17),
            label: Text(review == null ? 'Rate this experience' : 'Edit review'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandGreen,
              side: const BorderSide(color: AppColors.brandGreen),
            ),
          ),
        ],
      ),
    );
  }

  /// What the status means for the traveller, in a sentence or two.
  Widget _statusBanner(BuildContext context, ExperienceRequest r) {
    final provider = r.vendorName ?? 'The provider';
    final lines = <String>[];
    switch (r.status) {
      case ExperienceRequest.statusNew:
        lines.add('Waiting for $provider to reply. They usually reply within a day.');
        break;
      case ExperienceRequest.statusContacted:
        lines.add('$provider has been in touch. Your booking is confirmed only '
            'when they confirm it.');
        break;
      case ExperienceRequest.statusConfirmed:
        lines.add('Confirmed for ${_day(context, r.confirmedDate)}. Pay the '
            'provider directly at the location.');
        final last = r.freeCancellationLastDay;
        if (last != null) {
          lines.add(r.isLateToCancel()
              ? 'The free cancellation period ended on ${_day(context, last)}. '
                  'If you cancel now or do not attend, you may have to pay the '
                  'booking price.'
              : 'Free cancellation until the end of ${_day(context, last)}.');
        }
        break;
      case ExperienceRequest.statusCustomerCancelled:
        lines.add('You cancelled this on ${_day(context, r.cancelledAt)}.');
        if (r.lateCancellation) {
          lines.add('This was less than 72 hours before the booked day, so the '
              'provider may charge the booking price.');
        }
        break;
      case ExperienceRequest.statusProviderCancelled:
        lines.add('$provider cancelled this'
            '${r.cancelledAt == null ? '' : ' on ${_day(context, r.cancelledAt)}'}.');
        if (r.cancellationReason != null) {
          lines.add('Reason: ${r.cancellationReason}');
        }
        break;
      default:
        lines.add('This request is closed.');
    }

    final color = requestStatusColor(r.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Text(
                lines[i],
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: i == 0 ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Asks before cancelling, saying plainly whether it is free. Pops with the
/// (possibly empty) reason, or null to keep the request.
class _CancelDialog extends StatefulWidget {
  final ExperienceRequest request;

  const _CancelDialog({required this.request});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final late = r.isLateToCancel();
    final last = r.freeCancellationLastDay;
    final String explanation;
    if (!r.isConfirmed) {
      explanation = 'Your request has not been confirmed yet, so cancelling is free.';
    } else if (late) {
      explanation = 'This is less than 72 hours before your experience. Under the '
          'Experience Booking Terms you may have to pay the booking price.';
    } else {
      explanation = 'Cancelling is free until the end of '
          '${last == null ? 'the free period' : _day(context, last)}.';
    }

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(r.isConfirmed ? 'Cancel this booking?' : 'Cancel this request?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            explanation,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: late ? AppColors.error : AppColors.textSecondary,
              fontWeight: late ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            maxLines: 2,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(r.isConfirmed ? 'Cancel booking' : 'Cancel request'),
        ),
      ],
    );
  }
}
