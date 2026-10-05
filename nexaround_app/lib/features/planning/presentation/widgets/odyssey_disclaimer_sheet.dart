import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// The official legal disclaimer and user consent text for Odyssey travel planning.
const String kOdysseyDisclaimerText =
    "The 'Odyssey' travel planning itinerary is provided for informational and planning purposes only and does not constitute the provision or operation of any flight, hotel, transportation, activity, or other third-party travel service. Prices, availability, schedules, entry requirements, and other information may change and should be independently verified by you or with the relevant service provider before booking. All bookings and services are subject to the respective provider’s terms and conditions. By proceeding, you acknowledge that you are responsible for verifying your travel documents, visas, bookings, insurance, and other applicable requirements.\n\nNexaround is not responsible for changes, cancellations, delays, service quality, or actions of third-party providers.";

/// Displays a modal bottom sheet showing the complete Odyssey itinerary disclaimer and terms.
Future<void> showOdysseyDisclaimerModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      size: 20,
                      color: AppColors.brandGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Travel Planning Consent & Terms',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Important Odyssey advisory',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const SingleChildScrollView(
                  child: Text(
                    kOdysseyDisclaimerText,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(modalContext).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'I Understand & Agree',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A compact consent and disclaimer badge with a "View Terms" tap action.
class OdysseyConsentBanner extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const OdysseyConsentBanner({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: InkWell(
        onTap: () => showOdysseyDisclaimerModal(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: Color(0xFF64748B),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'By proceeding, you agree to the ',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    children: [
                      TextSpan(
                        text: 'Odyssey Travel & Planning Terms',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          color: Color(0xFF334155),
                        ),
                      ),
                      TextSpan(text: '.'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
