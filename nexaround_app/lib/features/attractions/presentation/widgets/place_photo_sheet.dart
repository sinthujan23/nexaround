import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/data/place_photos_service.dart';

/// "Add a photo" for a place that shows only its category icon. Returns the
/// sent photo (waiting for our team), or null when the traveller closed it.
Future<MyPlacePhoto?> showPlacePhotoSheet(
  BuildContext context, {
  required String placeId,
  required String placeName,
  double? latitude,
  double? longitude,
}) {
  return showModalBottomSheet<MyPlacePhoto>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (_) => _PlacePhotoSheet(
      placeId: placeId,
      placeName: placeName,
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

class _PlacePhotoSheet extends StatefulWidget {
  final String placeId;
  final String placeName;
  final double? latitude;
  final double? longitude;

  const _PlacePhotoSheet({
    required this.placeId,
    required this.placeName,
    this.latitude,
    this.longitude,
  });

  @override
  State<_PlacePhotoSheet> createState() => _PlacePhotoSheetState();
}

class _PlacePhotoSheetState extends State<_PlacePhotoSheet> {
  XFile? _picked;
  bool _consent = false;
  bool _sending = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    try {
      // Shrunk on the phone: a smaller upload, and the server re-encodes anyway.
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file != null && mounted) {
        setState(() {
          _picked = file;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the photo. Please try again.');
    }
  }

  Future<void> _send() async {
    if (_picked == null) return;
    if (!_consent) {
      setState(() => _error = 'Please confirm you took this photo.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await PlacePhotosService.upload(
      widget.placeId,
      filePath: _picked!.path,
      placeName: widget.placeName,
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    if (!mounted) return;
    if (result.sent) {
      Navigator.of(context).pop(result.photo);
      return;
    }
    setState(() {
      _sending = false;
      _error = result.error;
    });
  }

  Widget _sourceButton(IconData icon, String label, ImageSource source) => Expanded(
        child: OutlinedButton.icon(
          onPressed: _sending ? null : () => _pick(source),
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandGreen,
            side: const BorderSide(color: AppColors.brandGreen),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const Text('Add a photo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                widget.placeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (_picked != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.file(File(_picked!.path), fit: BoxFit.cover),
                  ),
                )
              else
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_rounded, size: 32, color: AppColors.textTertiary),
                      SizedBox(height: 8),
                      Text('A clear photo of the place itself',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _sourceButton(Icons.photo_camera_rounded, 'Camera', ImageSource.camera),
                  const SizedBox(width: 10),
                  _sourceButton(Icons.photo_library_rounded, 'Gallery', ImageSource.gallery),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _consent,
                onChanged: _sending ? null : (v) => setState(() {
                  _consent = v ?? false;
                  _error = null;
                }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.brandGreen,
                title: const Text(
                  'I took this photo, and nexAround may show it in the app with my first name and last initial.',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              const Text(
                'Our team checks every photo before it shows.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _sending || _picked == null ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
