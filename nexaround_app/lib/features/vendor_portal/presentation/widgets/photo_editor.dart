import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';

import '../vendor_ui.dart';

/// The photos of a package or of the business. New ones upload as soon as
/// they are picked; the first is the cover. [onBusy] is true while an upload
/// runs, so the form can refuse to save without those photos.
class PhotoEditor extends StatefulWidget {
  final VendorPortalApi api;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<bool> onBusy;

  const PhotoEditor({
    super.key,
    required this.api,
    required this.value,
    required this.onChanged,
    required this.onBusy,
  });

  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  final _picker = ImagePicker();
  int _uploading = 0;

  Future<void> _add() async {
    final picked = await _picker.pickMultiImage(maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() => _uploading = picked.length);
    widget.onBusy(true);
    try {
      final urls = await widget.api.uploadPhotos(picked.map((f) => f.path).toList());
      widget.onChanged([...widget.value, ...urls]);
    } catch (e) {
      if (mounted) {
        showVendorSnack(context, userMessageFor(e, action: 'upload the photos'), error: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = 0);
      widget.onBusy(false);
    }
  }

  void _remove(int i) => widget.onChanged([...widget.value]..removeAt(i));

  void _makeCover(int i) {
    final list = [...widget.value];
    final url = list.removeAt(i);
    widget.onChanged([url, ...list]);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < photos.length; i++) _tile(i, photos[i]),
            _addTile(),
          ],
        ),
        if (_uploading > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Uploading $_uploading photo${_uploading == 1 ? '' : 's'}… wait until this finishes before saving.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tile(int i, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(mediaUrl(url), fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceVariant)),
          if (i == 0)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Cover',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: PopupMenuButton<String>(
              tooltip: 'Photo options',
              icon: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.more_horiz_rounded, size: 16, color: Colors.white),
              ),
              onSelected: (action) => action == 'cover' ? _makeCover(i) : _remove(i),
              itemBuilder: (_) => [
                if (i != 0) const PopupMenuItem(value: 'cover', child: Text('Make cover photo')),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTile() {
    return InkWell(
      onTap: _uploading > 0 ? null : _add,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: AppColors.brandGreen),
            SizedBox(height: 4),
            Text('Add photos', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
