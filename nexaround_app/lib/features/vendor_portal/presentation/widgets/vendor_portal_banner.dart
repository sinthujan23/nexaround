import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../pages/vendor_portal_page.dart';

/// "Vendor portal" at the top of Experiences, for a traveller an admin gave
/// a business to manage. Takes no room for everyone else.
class VendorPortalBanner extends StatefulWidget {
  const VendorPortalBanner({super.key});

  @override
  State<VendorPortalBanner> createState() => _VendorPortalBannerState();
}

class _VendorPortalBannerState extends State<VendorPortalBanner> {
  List<VendorAccess> _access = const [];

  @override
  void initState() {
    super.initState();
    if (CacheService.isLoggedIn()) {
      // The last answer at once, then the server's.
      _access = VendorPortalApi.cachedAccess();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final access = await VendorPortalApi.access();
      if (mounted) setState(() => _access = access);
    } catch (_) {
      // Keep what was kept: none for someone never given a business.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_access.isEmpty) return const SizedBox.shrink();
    final names = _access.map((a) => a.vendorName).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openVendorPortal(context, access: _access),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.brandGreen, AppColors.brandGreenDark]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vendor portal',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      Text('Manage $names',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
