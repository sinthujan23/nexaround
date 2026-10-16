/// The Experience Booking Terms: what a traveller agrees to when they send a
/// request. Versioned on the server (Admin > Legal); every request carries the
/// version the traveller accepted.
class ExperienceTerms {
  final int version;
  final String title;

  /// "## " heading, "- " bullet, blank line between paragraphs. See
  /// LegalBody, which renders it.
  final String body;

  /// The few rules shown where people commit: the "Good to know" card, the
  /// request sheet and the confirmation.
  final List<String> highlights;
  final DateTime? updatedAt;

  /// Whether the signed-in traveller has accepted this version. False when
  /// signed out, so the request sheet shows the checkbox.
  final bool accepted;

  const ExperienceTerms({
    required this.version,
    required this.title,
    required this.body,
    this.highlights = const [],
    this.updatedAt,
    this.accepted = false,
  });

  factory ExperienceTerms.fromJson(Map<String, dynamic> json) {
    final highlights = json['highlights'];
    return ExperienceTerms(
      version: (json['version'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? 'Experience Booking Terms',
      body: json['body'] as String? ?? '',
      highlights: highlights is List
          ? highlights.whereType<String>().toList()
          : const [],
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      accepted: json['accepted'] as bool? ?? false,
    );
  }

  /// Shown before the terms have ever loaded (first open, offline): the same
  /// lines as the server's version 1, so the card is never blank.
  static const fallbackHighlights = [
    'Pay the provider directly at the location, by cash or card where accepted.',
    'Cancel at least 72 hours before the start, or the booking price may be due.',
    'Your request is confirmed only when the provider confirms it.',
    'Run by an independent local provider. Nexaround connects you.',
  ];
}
