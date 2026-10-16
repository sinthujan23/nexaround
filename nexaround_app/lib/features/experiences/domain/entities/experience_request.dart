import 'package:nexaround_app/features/experiences/domain/entities/experience_review.dart';

/// One request the traveller sent, as My requests shows it.
///
/// The server owns the rules (see enquiry_lifecycle.py): a request becomes a
/// booking when the provider confirms it for a date, and from then on the
/// free cancellation period ends at the end of [freeCancellationLastDay].
class ExperienceRequest {
  final String id;
  final String? packageId;
  final String packageTitle;
  final String? vendorName;
  final String? coverPhotoUrl;
  final String? vendorPhone;
  final String? vendorWhatsapp;
  final DateTime? preferredDate;
  final int? partySize;
  final String? pickupLocation;
  final String? message;
  final String status;
  final DateTime? createdAt;
  final DateTime? confirmedDate;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final bool lateCancellation;
  final DateTime? freeCancellationLastDay;
  final bool canCancel;

  /// The provider confirmed the booking and its day has come: the traveller
  /// may rate it. [review] is theirs, once written.
  final bool canReview;
  final MyExperienceReview? review;

  const ExperienceRequest({
    required this.id,
    required this.packageTitle,
    required this.status,
    this.packageId,
    this.vendorName,
    this.coverPhotoUrl,
    this.vendorPhone,
    this.vendorWhatsapp,
    this.preferredDate,
    this.partySize,
    this.pickupLocation,
    this.message,
    this.createdAt,
    this.confirmedDate,
    this.cancelledAt,
    this.cancellationReason,
    this.lateCancellation = false,
    this.freeCancellationLastDay,
    this.canCancel = false,
    this.canReview = false,
    this.review,
  });

  static const statusNew = 'new';
  static const statusContacted = 'contacted';
  static const statusConfirmed = 'confirmed';
  static const statusClosed = 'closed';
  static const statusCustomerCancelled = 'customer_cancelled';
  static const statusProviderCancelled = 'provider_cancelled';

  bool get isConfirmed => status == statusConfirmed;
  bool get isCancelled =>
      status == statusCustomerCancelled || status == statusProviderCancelled;

  /// The day it is for: the confirmed one once there is one.
  DateTime? get bookedDate => confirmedDate ?? preferredDate;

  /// Whether cancelling now would fall inside the 72 hours, judged on the
  /// traveller's own calendar: the last free day has ended for them. Only a
  /// confirmed booking can be cancelled late.
  bool isLateToCancel([DateTime? now]) {
    final last = freeCancellationLastDay;
    if (!isConfirmed || last == null) return false;
    final today = now ?? DateTime.now();
    final lastDay = DateTime(last.year, last.month, last.day);
    return DateTime(today.year, today.month, today.day).isAfter(lastDay);
  }

  factory ExperienceRequest.fromJson(Map<String, dynamic> json) {
    DateTime? day(String key) => DateTime.tryParse(json[key]?.toString() ?? '');
    String? text(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return ExperienceRequest(
      id: json['id']?.toString() ?? '',
      packageId: text('package_id'),
      packageTitle: text('package_title') ?? 'Experience',
      vendorName: text('vendor_name'),
      coverPhotoUrl: text('cover_photo_url'),
      vendorPhone: text('vendor_phone'),
      vendorWhatsapp: text('vendor_whatsapp'),
      preferredDate: day('preferred_date'),
      partySize: (json['party_size'] as num?)?.toInt(),
      pickupLocation: text('pickup_location'),
      message: text('message'),
      status: json['status']?.toString() ?? statusNew,
      createdAt: day('created_at')?.toLocal(),
      confirmedDate: day('confirmed_date'),
      cancelledAt: day('cancelled_at')?.toLocal(),
      cancellationReason: text('cancellation_reason'),
      lateCancellation: json['late_cancellation'] as bool? ?? false,
      freeCancellationLastDay: day('free_cancellation_last_day'),
      canCancel: json['can_cancel'] as bool? ?? false,
      canReview: json['can_review'] as bool? ?? false,
      review: json['review'] is Map<String, dynamic>
          ? MyExperienceReview.fromJson(json['review'] as Map<String, dynamic>)
          : null,
    );
  }
}
