import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';

/// Why the vendor cannot do the date asked: the server's
/// enquiry_lifecycle.DECLINE_REASONS. Only the label reaches the traveller.
const declineReasons = <String, String>{
  'fully_booked': 'Fully booked that day',
  'weather': 'Weather or sea conditions',
  'not_running': 'Not running that day',
  'other': 'Other reason',
};

/// "Sun 2 Nov 2026".
String requestDay(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
}

/// One request in a sheet at the foot of the screen, as tall as it needs:
/// the package's photo, then the request with its answers. [onAnswered]
/// runs after the sheet closes on an answer.
Future<void> showRequestSheet(
  BuildContext context,
  VendorRequest request,
  VendorPortalApi api, {
  required VoidCallback onAnswered,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(vendorGutter, 0, vendorGutter, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (request.photoUrl != null) ...[
              ClipRRect(
                borderRadius: AppRadii.brMd,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    mediaUrl(request.photoUrl!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppColors.surface),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            RequestCard(
              request: request,
              api: api,
              margin: EdgeInsets.zero,
              onAnswered: (_) {
                Navigator.pop(ctx);
                onAnswered();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Travellers' requests for the vendor's packages: package, date, guests and
/// price - never who asked. "To answer" is the to-do list, oldest first.
class VendorRequestsTab extends StatefulWidget {
  final VendorPortalApi api;

  /// Bumped by the portal to reload (a push, or a line in the bell).
  final ValueNotifier<int> changed;

  /// After an answer: Home's count follows.
  final VoidCallback? onAnswered;

  const VendorRequestsTab({super.key, required this.api, required this.changed, this.onAnswered});

  @override
  State<VendorRequestsTab> createState() => VendorRequestsTabState();
}

class VendorRequestsTabState extends State<VendorRequestsTab> {
  bool _all = false;
  // What the device kept, until the server answers.
  late VendorRequestPage? _page = widget.api.cachedRequests();
  late bool _fromCache = _page != null;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.changed.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    widget.changed.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final page = await widget.api.requests(scope: _all ? 'all' : 'open');
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _fromCache = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _filter(bool all) {
    if (all == _all) return;
    setState(() {
      _all = all;
      _page = all ? null : widget.api.cachedRequests();
      _fromCache = _page != null;
    });
    _load();
  }

  /// Opens one request (from a push or the bell) over the list.
  Future<void> openRequest(String id) async {
    try {
      final request = await widget.api.request(id);
      if (!mounted) return;
      await showRequestSheet(context, request, widget.api, onAnswered: _answered);
    } catch (e) {
      if (mounted) showVendorSnack(context, userMessageFor(e, action: 'open the request'), error: true);
    }
  }

  /// The portal reloads every list (this one too) through [changed].
  void _answered() {
    if (widget.onAnswered != null) {
      widget.onAnswered!();
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final requests = page?.requests ?? const <VendorRequest>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
        children: [
          const Text('Requests',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          const Text('NexAround arranges each booking with the traveller.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          _filters(page),
          const SizedBox(height: 14),
          if (_error != null && _fromCache) const VendorSavedNote(),
          if (_error != null && page == null)
            VendorEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn’t load requests',
              message: userMessageFor(_error),
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (page == null || (_loading && requests.isEmpty && _error == null && page.total > 0))
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (requests.isEmpty)
            VendorEmptyState(
              icon: Icons.inbox_outlined,
              title: _all ? 'No requests yet' : 'Nothing to answer',
              message: _all
                  ? 'When a traveller asks for one of your packages, it shows here and you get a notification.'
                  : 'You have answered every request. New ones show here and you get a notification.',
            )
          else
            for (final r in requests)
              RequestCard(
                key: ValueKey(r.id),
                request: r,
                api: widget.api,
                onAnswered: (_) => _answered(),
              ),
        ],
      ),
    );
  }

  /// To answer / All, as one segmented control (like Reviews).
  Widget _filters(VendorRequestPage? page) {
    final waiting = page?.waiting ?? 0;
    Widget segment(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  boxShadow: selected ? AppShadows.sm : null,
                ),
                child: Text(label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    )),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Row(
        children: [
          segment(waiting > 0 && !_all ? 'To answer ($waiting)' : 'To answer', !_all, () => _filter(false)),
          segment('All requests', _all, () => _filter(true)),
        ],
      ),
    );
  }
}

/// One request: what was asked, where it stands, and the answers while it
/// is open.
class RequestCard extends StatefulWidget {
  final VendorRequest request;
  final VendorPortalApi api;
  final ValueChanged<VendorRequest> onAnswered;
  final EdgeInsetsGeometry margin;

  const RequestCard({
    super.key,
    required this.request,
    required this.api,
    required this.onAnswered,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  State<RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<RequestCard> {
  bool _sending = false;

  VendorRequest get r => widget.request;

  (String, Color) get _standing => switch (r.status) {
        'confirmed' => ('Confirmed for ${requestDay(r.confirmedDate!)}', AppColors.success),
        'customer_cancelled' when r.offerResponse == 'declined' =>
          ('The traveller declined your date', AppColors.textTertiary),
        'customer_cancelled' => ('Cancelled by the traveller', AppColors.textTertiary),
        'provider_cancelled' => ('Cancelled by you', AppColors.textTertiary),
        'closed' => ('Closed', AppColors.textTertiary),
        _ when r.answer == 'other_date' =>
          ('You offered ${requestDay(r.offeredDate!)} · waiting for the traveller', const Color(0xFFB7791F)),
        _ => ('Waiting for your answer', AppColors.error),
      };

  Future<void> _send(String action, String done, {DateTime? day, String? reason, String? note}) async {
    setState(() => _sending = true);
    try {
      final updated = await widget.api.answer(r.id, action, day: day, reason: reason, note: note);
      if (!mounted) return;
      showVendorSnack(context, done);
      widget.onAnswered(updated);
    } catch (e) {
      if (mounted) showVendorSnack(context, userMessageFor(e, action: 'send your answer'), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<DateTime?> _pickDay(String help) {
    final today = DateUtils.dateOnly(DateTime.now());
    return showDatePicker(
      context: context,
      helpText: help,
      initialDate: r.preferredDate != null && !r.preferredDate!.isBefore(today) ? r.preferredDate! : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
  }

  Future<void> _confirm() async {
    DateTime? day;
    if (r.flexible) {
      day = await _pickDay('The day you can do it');
      if (day == null || !mounted) return;
    }
    final when = day ?? r.preferredDate!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm for ${requestDay(when)}?'),
        content: Text('${r.partySize != null ? '${r.partySize} guests. ' : ''}'
            'NexAround tells the traveller at once.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm booking')),
        ],
      ),
    );
    if (ok == true) await _send('confirmed', 'Confirmed. The traveller has been told.', day: day);
  }

  Future<void> _decline() async {
    final answer = await showModalBottomSheet<_Decline>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DeclineSheet(request: r, pickDay: _pickDay),
    );
    if (answer == null || !mounted) return;
    await _send(
      answer.offer ? 'other_date' : 'cancelled',
      answer.offer
          ? 'Sent. The traveller will accept or decline the new date.'
          : 'Cancelled. The traveller has been told.',
      day: answer.day,
      reason: answer.reason,
      note: answer.note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _standing;
    return VendorCard(
      margin: widget.margin,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        // As tall as its content: in a sheet it must not fill the screen.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.packageTitle,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25)),
                    const SizedBox(height: 2),
                    Text('${r.reference} · received ${requestDay(r.createdAt.toLocal())}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadii.brSm),
            child: Column(
              children: [
                _fact(Icons.event_outlined, 'Date',
                    r.flexible ? 'Flexible: you choose' : requestDay(r.preferredDate!)),
                _fact(Icons.group_outlined, 'Guests', r.partySize?.toString() ?? '—'),
                _fact(Icons.sell_outlined, 'Price', r.priceLabel ?? 'On request', last: true),
              ],
            ),
          ),
          if (r.canAnswer) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : _decline,
                    // Narrow padding: the label must fit a phone's half width.
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Can’t do this date', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: VendorPrimaryButton(
                    label: _sending ? 'Sending…' : 'Confirm',
                    onPressed: _sending ? null : _confirm,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String label, String value, {bool last = false}) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.textTertiary),
            const SizedBox(width: 10),
            SizedBox(
              width: 58,
              child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _Decline {
  final bool offer;
  final DateTime? day;
  final String reason;
  final String? note;

  const _Decline({required this.offer, this.day, required this.reason, this.note});
}

/// "Can't do this date": offer another date (NexAround checks it with the
/// traveller), or cancel when there is none; a reason either way.
class _DeclineSheet extends StatefulWidget {
  final VendorRequest request;
  final Future<DateTime?> Function(String help) pickDay;

  const _DeclineSheet({required this.request, required this.pickDay});

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  bool _offer = true;
  DateTime? _day;
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _ready => _reason != null && (!_offer || _day != null);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(vendorGutter, 0, vendorGutter, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Can’t do this date',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              const SizedBox(height: 4),
              Text(
                widget.request.flexible
                    ? '${widget.request.packageTitle} · flexible date'
                    : '${widget.request.packageTitle} · ${requestDay(widget.request.preferredDate!)}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _choice('Offer another date', _offer, () => setState(() => _offer = true))),
                  const SizedBox(width: 8),
                  Expanded(child: _choice('No other date', !_offer, () => setState(() => _offer = false))),
                ],
              ),
              const SizedBox(height: 14),
              if (_offer) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final day = await widget.pickDay('The date you can offer');
                    if (day != null) setState(() => _day = day);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_day == null ? 'Choose the date you can offer' : requestDay(_day!)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                icon: vendorDropdownIcon,
                style: vendorDropdownText(context),
                decoration: vendorInput('Why not the date asked?'),
                items: [
                  for (final e in declineReasons.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _reason = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: vendorInput('Note to NexAround (optional)',
                    hint: 'e.g. Mornings only that week', helper: 'Only NexAround sees this.'),
              ),
              const SizedBox(height: 8),
              Text(
                _offer
                    ? 'The traveller accepts or declines the new date in the NexAround app.'
                    : 'The traveller is told you cannot do it, with the reason only.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _offer
                  ? VendorPrimaryButton(
                      label: 'Send to NexAround',
                      onPressed: _ready ? () => Navigator.pop(context, _answer()) : null,
                    )
                  : ElevatedButton(
                      onPressed: _ready ? () => Navigator.pop(context, _answer()) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: AppRadii.brMd),
                      ),
                      child: const Text('Cancel request'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  _Decline _answer() => _Decline(
        offer: _offer,
        day: _offer ? _day : null,
        reason: _reason!,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              )),
        ),
      );
}
