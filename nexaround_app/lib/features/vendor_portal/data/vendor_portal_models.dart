/// What the vendor screens read and write: the partner API's shapes
/// (nexaround_backend/app/schemas/partner.py), as the web portal at
/// partner.nexaround.com uses them.
///
/// None of these carries a traveller's name or contact: the partner API never
/// sends one. A request reaches the vendor only as a feed line ("New request:
/// Desert Safari · Sun 25 Oct · 4 guests").
library;

import 'dart:convert';

/// A form's edits moved onto a fresher copy of its record, so a save never
/// sends back an older copy's other fields: [mine] is the form, edited from
/// [base]; each field the person changed keeps their value, every other
/// field takes [fresh]'s. All three are `toJson()` bodies.
Map<String, dynamic> rebaseEdits(
  Map<String, dynamic> base,
  Map<String, dynamic> mine,
  Map<String, dynamic> fresh,
) =>
    {
      ...fresh,
      for (final e in mine.entries)
        if (jsonEncode(e.value) != jsonEncode(base[e.key])) e.key: e.value,
    };

/// One price a package is sold at (the server's PriceOptionBase). No dollar
/// price: only NexAround sets that, and the server keeps it by [id]. A blank
/// min is 1 and a blank max is the package's Max participants.
class VendorPriceOption {
  /// The server's id; null for a price added in this form.
  final String? id;

  /// Stays the same while the row is edited, so its fields keep their place
  /// when a row above is removed.
  final String key;
  final double? amount;
  final String basis;
  final int? minPeople;
  final int? maxPeople;

  VendorPriceOption({
    this.id,
    String? key,
    this.amount,
    this.basis = 'per_person',
    this.minPeople,
    this.maxPeople,
  }) : key = key ?? id ?? 'new-${_newKeys++}';

  static int _newKeys = 0;

  factory VendorPriceOption.fromJson(Map<String, dynamic> json) => VendorPriceOption(
        id: json['id']?.toString(),
        amount: _double(json['amount']),
        basis: (json['basis'] ?? 'per_person').toString(),
        minPeople: _int(json['min_people']),
        maxPeople: _int(json['max_people']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'basis': basis,
        'min_people': minPeople,
        'max_people': maxPeople,
      };

  VendorPriceOption copyWith({
    double? Function()? amount,
    String? basis,
    int? Function()? minPeople,
    int? Function()? maxPeople,
  }) =>
      VendorPriceOption(
        id: id,
        key: key,
        amount: amount != null ? amount() : this.amount,
        basis: basis ?? this.basis,
        minPeople: minPeople != null ? minPeople() : this.minPeople,
        maxPeople: maxPeople != null ? maxPeople() : this.maxPeople,
      );
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

double? _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

List<String> _strings(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Where a vendor's own edits stand: NexAround checks a package's content
/// and the profile before travellers see them, while the live version keeps
/// showing (the server's services/vendor_review). Availability and the
/// Show in app switch apply at once.
class VendorReviewState {
  /// "approved" (nothing waiting), "pending" or "changes_requested".
  final String status;

  /// What NexAround asked to change, when it sent the edit back.
  final String? note;
  final DateTime? submittedAt;

  const VendorReviewState({this.status = 'approved', this.note, this.submittedAt});

  factory VendorReviewState.fromJson(Map<String, dynamic> json) => VendorReviewState(
        status: (json['review_status'] ?? 'approved').toString(),
        note: json['review_note'] as String?,
        submittedAt: _date(json['submitted_at']),
      );

  bool get isPending => status == 'pending';
  bool get changesRequested => status == 'changes_requested';

  Map<String, dynamic> toJson() => {
        'review_status': status,
        'review_note': note,
        'submitted_at': submittedAt?.toIso8601String(),
      };
}

/// A vendor the signed-in traveller has been given to manage.
class VendorAccess {
  final String vendorId;
  final String vendorName;
  final String? logoUrl;

  const VendorAccess({required this.vendorId, required this.vendorName, this.logoUrl});

  factory VendorAccess.fromJson(Map<String, dynamic> json) => VendorAccess(
        vendorId: json['vendor_id'].toString(),
        vendorName: (json['vendor_name'] ?? '').toString(),
        logoUrl: json['logo_url'] as String?,
      );
}

/// Who is signed in to the vendor screens, and for which business.
class VendorMe {
  final String loginId;
  final String? displayName;
  final String vendorId;
  final String vendorName;
  final bool vendorIsActive;

  const VendorMe({
    required this.loginId,
    this.displayName,
    required this.vendorId,
    required this.vendorName,
    required this.vendorIsActive,
  });

  factory VendorMe.fromJson(Map<String, dynamic> json) => VendorMe(
        loginId: json['login_id'].toString(),
        displayName: json['display_name'] as String?,
        vendorId: json['vendor_id'].toString(),
        vendorName: (json['vendor_name'] ?? '').toString(),
        vendorIsActive: json['vendor_is_active'] == true,
      );
}

/// Days travellers cannot book, inclusive at both ends.
class BlockedRange {
  final DateTime start;
  final DateTime end;

  const BlockedRange(this.start, this.end);

  factory BlockedRange.fromJson(Map<String, dynamic> json) => BlockedRange(
        DateTime.parse(json['start'].toString()),
        DateTime.parse(json['end'].toString()),
      );

  Map<String, dynamic> toJson() => {'start': _day(start), 'end': _day(end)};

  @override
  bool operator ==(Object other) =>
      other is BlockedRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class VendorPackage {
  final String? id;
  final String title;
  final String summary;
  final String description;
  final String category;
  final List<String> tags;
  final List<String> photoUrls;

  /// {photo url: tiny base64 WebP} from the server, drawn blurred while each
  /// photo loads. Read-only: never sent back in [toJson].
  final Map<String, String> imagePreviews;
  final List<BlockedRange> unavailableRanges;
  final double? priceAmount;
  final String priceCurrency;
  final String priceBasis;

  /// Every price, first one first. The server mirrors the first into the
  /// three fields above. Empty means "Price on request".
  final List<VendorPriceOption> priceOptions;
  final int? durationMinutes;
  final int? maxParticipants;
  final int? bookingWindowDays;
  final List<String> inclusions;
  final List<String> languages;
  /// Where travellers meet the vendor: NexAround sets it, so these are
  /// shown, never sent.
  final bool usesVendorLocation;
  final String meetingPointAddress;
  final bool isActive;
  final double? latitude;
  final double? longitude;

  /// The server's word, not the form's: it also needs the whole listing to
  /// be live, which only NexAround can switch.
  final bool isPublished;

  /// False for a package the vendor added that NexAround has not approved
  /// yet: travellers cannot see it.
  final bool isApproved;

  /// The fields above are what the vendor last asked for; this says whether
  /// they wait for NexAround.
  final VendorReviewState review;

  const VendorPackage({
    this.id,
    this.title = '',
    this.summary = '',
    this.description = '',
    this.category = 'boat',
    this.tags = const [],
    this.photoUrls = const [],
    this.imagePreviews = const {},
    this.unavailableRanges = const [],
    this.priceAmount,
    this.priceCurrency = 'LKR',
    this.priceBasis = 'per_person',
    this.priceOptions = const [],
    this.durationMinutes,
    this.maxParticipants,
    this.bookingWindowDays,
    this.inclusions = const [],
    this.languages = const [],
    this.usesVendorLocation = true,
    this.meetingPointAddress = '',
    this.isActive = true,
    this.latitude,
    this.longitude,
    this.isPublished = false,
    this.isApproved = true,
    this.review = const VendorReviewState(),
  });

  factory VendorPackage.fromJson(Map<String, dynamic> json) => VendorPackage(
        id: json['id']?.toString(),
        title: (json['title'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        category: (json['category'] ?? 'other').toString(),
        tags: _strings(json['tags']),
        photoUrls: _strings(json['photo_urls']),
        imagePreviews: _stringMap(json['image_previews']),
        unavailableRanges: ((json['unavailable_ranges'] as List?) ?? const [])
            .map((r) => BlockedRange.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        priceAmount: _double(json['price_amount']),
        priceCurrency: (json['price_currency'] ?? 'LKR').toString(),
        priceBasis: (json['price_basis'] ?? 'per_person').toString(),
        priceOptions: ((json['price_options'] as List?) ?? const [])
            .map((o) => VendorPriceOption.fromJson(Map<String, dynamic>.from(o as Map)))
            .toList(),
        durationMinutes: _int(json['duration_minutes']),
        maxParticipants: _int(json['max_participants']),
        bookingWindowDays: _int(json['booking_window_days']),
        inclusions: _strings(json['inclusions']),
        languages: _strings(json['languages']),
        usesVendorLocation: json['uses_vendor_location'] != false,
        meetingPointAddress: (json['meeting_point_address'] ?? '').toString(),
        isActive: json['is_active'] != false,
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        isPublished: json['is_published'] == true,
        isApproved: json['is_approved'] != false,
        review: VendorReviewState.fromJson(json),
      );

  /// The body of a create or update, which is a full replacement. No
  /// meeting point: only NexAround sets where travellers meet the vendor.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'summary': summary.trim().isEmpty ? null : summary.trim(),
        'description': description.trim().isEmpty ? null : description,
        'category': category,
        'tags': tags,
        'photo_urls': photoUrls,
        'unavailable_ranges': unavailableRanges.map((r) => r.toJson()).toList(),
        'price_amount': priceAmount,
        'price_currency': priceCurrency,
        'price_basis': priceBasis,
        // A row with no price is dropped; none left is "Price on request".
        'price_options': [
          for (final o in priceOptions)
            if (o.amount != null) o.toJson(),
        ],
        'duration_minutes': durationMinutes,
        'max_participants': maxParticipants,
        'booking_window_days': bookingWindowDays,
        'inclusions': inclusions,
        'languages': languages,
        'is_active': isActive,
      };

  VendorPackage copyWith({
    String? title,
    String? summary,
    String? description,
    String? category,
    List<String>? photoUrls,
    List<BlockedRange>? unavailableRanges,
    double? Function()? priceAmount,
    String? priceCurrency,
    String? priceBasis,
    List<VendorPriceOption>? priceOptions,
    int? Function()? durationMinutes,
    int? Function()? maxParticipants,
    int? Function()? bookingWindowDays,
    List<String>? inclusions,
    List<String>? languages,
    bool? isActive,
  }) =>
      VendorPackage(
        id: id,
        title: title ?? this.title,
        summary: summary ?? this.summary,
        description: description ?? this.description,
        category: category ?? this.category,
        tags: tags,
        photoUrls: photoUrls ?? this.photoUrls,
        unavailableRanges: unavailableRanges ?? this.unavailableRanges,
        priceAmount: priceAmount != null ? priceAmount() : this.priceAmount,
        priceCurrency: priceCurrency ?? this.priceCurrency,
        priceBasis: priceBasis ?? this.priceBasis,
        priceOptions: priceOptions ?? this.priceOptions,
        durationMinutes: durationMinutes != null ? durationMinutes() : this.durationMinutes,
        maxParticipants: maxParticipants != null ? maxParticipants() : this.maxParticipants,
        bookingWindowDays:
            bookingWindowDays != null ? bookingWindowDays() : this.bookingWindowDays,
        inclusions: inclusions ?? this.inclusions,
        languages: languages ?? this.languages,
        usesVendorLocation: usesVendorLocation,
        meetingPointAddress: meetingPointAddress,
        isActive: isActive ?? this.isActive,
        latitude: latitude,
        longitude: longitude,
        isPublished: isPublished,
        isApproved: isApproved,
        review: review,
      );

  /// [body] (a [toJson] body) as a package, with what only the server says
  /// - id, publish and review state, meeting point - taken from this one.
  VendorPackage withContent(Map<String, dynamic> body) => VendorPackage.fromJson({
        ...body,
        'id': id,
        'is_published': isPublished,
        'is_approved': isApproved,
        'uses_vendor_location': usesVendorLocation,
        'meeting_point_address': meetingPointAddress,
        'latitude': latitude,
        'longitude': longitude,
        ...review.toJson(),
      });

  /// "Not live yet", "Live", "Hidden" or "On, not visible", as the web
  /// portal says it.
  String get visibility {
    if (!isApproved) return 'Not live yet';
    if (!isActive) return 'Hidden';
    return isPublished ? 'Live' : 'On, not visible';
  }
}

class VendorStats {
  final int packagesTotal;
  final int packagesPublished;

  /// Requests the vendor has not answered yet.
  final int requestsWaiting;

  const VendorStats({this.packagesTotal = 0, this.packagesPublished = 0, this.requestsWaiting = 0});

  factory VendorStats.fromJson(Map<String, dynamic> json) => VendorStats(
        packagesTotal: _int(json['packages_total']) ?? 0,
        packagesPublished: _int(json['packages_published']) ?? 0,
        requestsWaiting: _int(json['requests_waiting']) ?? 0,
      );
}

/// A traveller's request as the vendor sees it: the package, the date, the
/// guests and the price chosen. Never who asked, how to reach them, where to
/// pick them up or what they wrote: NexAround arranges the booking.
class VendorRequest {
  final String id;

  /// "#3F9A1C", to name the request to NexAround.
  final String reference;
  final String packageTitle;

  /// Null when the traveller is flexible about the day.
  final DateTime? preferredDate;
  final DateTime? confirmedDate;
  final int? partySize;
  final String? priceLabel;

  /// new | contacted | confirmed | closed | customer_cancelled | provider_cancelled
  final String status;

  /// The vendor's own answer: confirmed | other_date | cancelled.
  final String? answer;
  final DateTime? offeredDate;
  final String? reason;

  /// The traveller's answer to [offeredDate]: accepted | declined.
  final String? offerResponse;
  final bool canAnswer;
  final DateTime createdAt;

  const VendorRequest({
    required this.id,
    required this.reference,
    required this.packageTitle,
    this.preferredDate,
    this.confirmedDate,
    this.partySize,
    this.priceLabel,
    required this.status,
    this.answer,
    this.offeredDate,
    this.reason,
    this.offerResponse,
    this.canAnswer = false,
    required this.createdAt,
  });

  factory VendorRequest.fromJson(Map<String, dynamic> json) => VendorRequest(
        id: json['id'].toString(),
        reference: (json['reference'] ?? '').toString(),
        packageTitle: (json['package_title'] ?? 'Experience').toString(),
        preferredDate: _date(json['preferred_date']),
        confirmedDate: _date(json['confirmed_date']),
        partySize: _int(json['party_size']),
        priceLabel: json['price_label'] as String?,
        status: (json['status'] ?? 'new').toString(),
        answer: json['vendor_response'] as String?,
        offeredDate: _date(json['vendor_offered_date']),
        reason: json['vendor_response_reason'] as String?,
        offerResponse: json['offer_response'] as String?,
        canAnswer: json['can_answer'] == true,
        createdAt: _date(json['created_at']) ?? DateTime.now(),
      );

  bool get flexible => preferredDate == null;

  /// Open and not answered yet: the vendor's to-do.
  bool get waiting => canAnswer && answer == null;
}

class VendorRequestPage {
  final List<VendorRequest> requests;
  final int total;
  final int waiting;

  const VendorRequestPage({this.requests = const [], this.total = 0, this.waiting = 0});

  factory VendorRequestPage.fromJson(Map<String, dynamic> json) => VendorRequestPage(
        requests: ((json['requests'] as List?) ?? const [])
            .map((r) => VendorRequest.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        total: _int(json['total']) ?? 0,
        waiting: _int(json['waiting']) ?? 0,
      );
}

/// A traveller's rating, as any traveller sees it in the app: a display
/// name, no account id and no contact.
class VendorReview {
  final String id;
  final String? packageTitle;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime? createdAt;
  final String? vendorReply;
  final DateTime? vendorRepliedAt;

  const VendorReview({
    required this.id,
    this.packageTitle,
    required this.reviewerName,
    required this.rating,
    this.comment,
    this.createdAt,
    this.vendorReply,
    this.vendorRepliedAt,
  });

  factory VendorReview.fromJson(Map<String, dynamic> json) => VendorReview(
        id: json['id'].toString(),
        packageTitle: json['package_title'] as String?,
        reviewerName: (json['reviewer_name'] ?? 'Traveller').toString(),
        rating: _int(json['rating']) ?? 0,
        comment: json['comment'] as String?,
        createdAt: _date(json['created_at']),
        vendorReply: json['vendor_reply'] as String?,
        vendorRepliedAt: _date(json['vendor_replied_at']),
      );
}

class VendorReviewPage {
  final List<VendorReview> reviews;
  final int total;
  final double? average;
  final int reviewCount;
  final int unanswered;

  const VendorReviewPage({
    this.reviews = const [],
    this.total = 0,
    this.average,
    this.reviewCount = 0,
    this.unanswered = 0,
  });

  factory VendorReviewPage.fromJson(Map<String, dynamic> json) => VendorReviewPage(
        reviews: ((json['reviews'] as List?) ?? const [])
            .map((r) => VendorReview.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        total: _int(json['total']) ?? 0,
        average: _double(json['average']),
        reviewCount: _int(json['review_count']) ?? 0,
        unanswered: _int(json['unanswered']) ?? 0,
      );
}

/// The business profile. Where the business is (address, city, country, map
/// point), its website, phone, WhatsApp and the socials are shown but only
/// NexAround sets them: travellers reach the business through NexAround.
/// What the vendor can change waits for NexAround's review ([review]).
class VendorProfile {
  final String name;
  final String description;
  final double? latitude;
  final double? longitude;
  final String address;
  final String city;
  final String? countryCode;
  final String contactEmail;
  final String website;
  final String? logoUrl;
  final List<String> photoUrls;
  final String? contactPhone;
  final String? contactWhatsapp;
  final String? contactInstagram;
  final String? contactFacebook;
  final String? contactX;
  final VendorReviewState review;

  const VendorProfile({
    this.name = '',
    this.description = '',
    this.latitude,
    this.longitude,
    this.address = '',
    this.city = '',
    this.countryCode,
    this.contactEmail = '',
    this.website = '',
    this.logoUrl,
    this.photoUrls = const [],
    this.contactPhone,
    this.contactWhatsapp,
    this.contactInstagram,
    this.contactFacebook,
    this.contactX,
    this.review = const VendorReviewState(),
  });

  factory VendorProfile.fromJson(Map<String, dynamic> json) => VendorProfile(
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        address: (json['address'] ?? '').toString(),
        city: (json['city'] ?? '').toString(),
        countryCode: (json['country_code'] as String?)?.toUpperCase(),
        contactEmail: (json['contact_email'] ?? '').toString(),
        website: (json['website'] ?? '').toString(),
        logoUrl: json['logo_url'] as String?,
        photoUrls: _strings(json['photo_urls']),
        contactPhone: json['contact_phone'] as String?,
        contactWhatsapp: json['contact_whatsapp'] as String?,
        contactInstagram: json['contact_instagram'] as String?,
        contactFacebook: json['contact_facebook'] as String?,
        contactX: json['contact_x'] as String?,
        review: VendorReviewState.fromJson(json),
      );

  /// Only the fields a vendor may change (PartnerVendorProfileUpdate); the
  /// ones NexAround sets are left out, and the server would drop them anyway.
  Map<String, dynamic> toJson() {
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    return {
      'name': name.trim(),
      'description': blank(description),
      'contact_email': blank(contactEmail),
      'logo_url': logoUrl,
      'photo_urls': photoUrls,
    };
  }

  /// [json] (a [toJson] body) with everything NexAround sets - which the
  /// body leaves out - taken from this profile.
  VendorProfile withManagedFrom(Map<String, dynamic> json) => VendorProfile.fromJson({
        ...json,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'city': city,
        'country_code': countryCode,
        'website': website,
        'contact_phone': contactPhone,
        'contact_whatsapp': contactWhatsapp,
        'contact_instagram': contactInstagram,
        'contact_facebook': contactFacebook,
        'contact_x': contactX,
        ...review.toJson(),
      });

  VendorProfile copyWith({
    String? name,
    String? description,
    String? contactEmail,
    List<String>? photoUrls,
  }) =>
      VendorProfile(
        name: name ?? this.name,
        description: description ?? this.description,
        latitude: latitude,
        longitude: longitude,
        address: address,
        city: city,
        countryCode: countryCode,
        contactEmail: contactEmail ?? this.contactEmail,
        website: website,
        logoUrl: logoUrl,
        photoUrls: photoUrls ?? this.photoUrls,
        contactPhone: contactPhone,
        contactWhatsapp: contactWhatsapp,
        contactInstagram: contactInstagram,
        contactFacebook: contactFacebook,
        contactX: contactX,
        review: review,
      );
}

/// One line of the vendor's notifications, the same feed as the web bell.
class VendorActivityItem {
  final String id;
  final String kind;
  final String title;
  final String? body;
  final String actor;
  final String? actorName;
  final String? packageId;

  /// The request a line is about, which a tap opens.
  final String? enquiryId;
  final DateTime createdAt;

  const VendorActivityItem({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    required this.actor,
    this.actorName,
    this.packageId,
    this.enquiryId,
    required this.createdAt,
  });

  factory VendorActivityItem.fromJson(Map<String, dynamic> json) => VendorActivityItem(
        id: json['id'].toString(),
        kind: (json['kind'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        body: json['body'] as String?,
        actor: (json['actor'] ?? '').toString(),
        actorName: json['actor_name'] as String?,
        packageId: json['package_id']?.toString(),
        enquiryId: json['enquiry_id']?.toString(),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
      );
}

class VendorActivityPage {
  final List<VendorActivityItem> items;
  final bool hasMore;
  final int unread;
  final DateTime? seenAt;

  const VendorActivityPage({
    this.items = const [],
    this.hasMore = false,
    this.unread = 0,
    this.seenAt,
  });

  factory VendorActivityPage.fromJson(Map<String, dynamic> json) => VendorActivityPage(
        items: ((json['items'] as List?) ?? const [])
            .map((r) => VendorActivityItem.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        hasMore: json['has_more'] == true,
        unread: _int(json['unread']) ?? 0,
        seenAt: _date(json['seen_at']),
      );
}

/// The Provider Agreement and whether this vendor still has to accept it.
class PartnerAgreement {
  final int version;
  final String title;
  final String body;
  final List<String> highlights;
  final int? acceptedVersion;

  /// True until this version is accepted: the screens stay behind it.
  final bool mustAccept;

  const PartnerAgreement({
    required this.version,
    required this.title,
    required this.body,
    this.highlights = const [],
    this.acceptedVersion,
    required this.mustAccept,
  });

  factory PartnerAgreement.fromJson(Map<String, dynamic> json) {
    final doc = Map<String, dynamic>.from(json['document'] as Map);
    return PartnerAgreement(
      version: _int(doc['version']) ?? 1,
      title: (doc['title'] ?? 'Provider Agreement').toString(),
      body: (doc['body'] ?? '').toString(),
      highlights: _strings(doc['highlights']),
      acceptedVersion: _int(json['accepted_version']),
      mustAccept: json['required'] == true,
    );
  }
}

/// `{"url": "preview"}` from the API; anything else is skipped.
Map<String, String> _stringMap(dynamic value) {
  if (value is! Map) return const {};
  final out = <String, String>{};
  value.forEach((key, v) {
    if (key is String && v is String && v.isNotEmpty) out[key] = v;
  });
  return out;
}
