import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/services/google_places_service.dart';
import '../../data/datasources/travel_stories_service.dart';
import '../../../../core/widgets/country_picker_sheet.dart';

class PostStorySheet extends StatefulWidget {
  final Function(TravelStory) onStorySubmitted;
  final double userLatitude;
  final double userLongitude;
  final TravelStory? editStory;

  const PostStorySheet({
    super.key,
    required this.onStorySubmitted,
    required this.userLatitude,
    required this.userLongitude,
    this.editStory,
  });

  @override
  State<PostStorySheet> createState() => _PostStorySheetState();
}

class _PostStorySheetState extends State<PostStorySheet> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedCategory = '💎 Hidden Gem';
  List<File> _selectedImages = [];
  List<String> _existingImageUrls = [];
  bool _isPublic = true; // New field for privacy toggle
  final ImagePicker _picker = ImagePicker();

  double? _selectedLatitude;
  double? _selectedLongitude;

  String? _selectedCountry;
  DateTime? _selectedTravelDate;

  final List<String> _categories = [
    '💎 Hidden Gem',
    '🧭 Offbeat Place',
    '🤫 Local Secret',
    '🌅 Scenic Viewpoint',
    '🍔 Food Spot',
  ];

  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoadingSuggestions = false;
  Timer? _debounceTimer;

  void _onLocationChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
      });
    }
  }

  Future<void> _fetchSuggestions(String input) async {
    if (input.trim().isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }
    setState(() => _isLoadingSuggestions = true);
    try {
      final results = await GooglePlacesService.getAutocompleteSuggestions(
        input: input,
        latitude: widget.userLatitude,
        longitude: widget.userLongitude,
      );
      if (mounted) {
        setState(() {
          _suggestions = results;
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSuggestions = false);
      }
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    final desc = suggestion['description'] as String;
    final placeId = suggestion['place_id'] as String;

    _locationController.text = (suggestion['main_text'] as String).isNotEmpty
        ? suggestion['main_text'] as String
        : desc;

    setState(() {
      _suggestions = [];
    });

    final details = await GooglePlacesService.getPlaceDetails(placeId);
    if (details != null) {
      print('Resolved place coords: ${details.latitude}, ${details.longitude}');
      _selectedLatitude = details.latitude;
      _selectedLongitude = details.longitude;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.editStory != null) {
      final story = widget.editStory!;
      _locationController.text = story.locationName;
      _descriptionController.text = story.description;
      _selectedCategory = story.category;
      _isPublic = story.isPublic;
      _selectedLatitude = story.latitude;
      _selectedLongitude = story.longitude;
      _existingImageUrls = story.imageUrls.isNotEmpty
          ? story.imageUrls
          : [story.imageUrl];
      _selectedCountry = story.country;
      _selectedTravelDate = story.travelDate;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          maxWidth: 1080,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (pickedFiles.isNotEmpty) {
          setState(() {
            _selectedImages.addAll(pickedFiles.map((f) => File(f.path)));
          });
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1080,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (pickedFile != null) {
          setState(() {
            _selectedImages.add(File(pickedFile.path));
          });
        }
      }
    } catch (e) {
      print('⚠️ Error picking images: $e');
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: AppColors.brandGreen,
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt,
                  color: AppColors.brandGreen,
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();

    if (location.isEmpty ||
        description.isEmpty ||
        (_selectedImages.isEmpty && _existingImageUrls.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields and attach at least one photo'),
        ),
      );
      return;
    }

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.brandGreen),
      ),
    );

    List<String> finalUrls = List.from(_existingImageUrls);
    if (_selectedImages.isNotEmpty) {
      try {
        final filePaths = _selectedImages.map((f) => f.path).toList();
        final uploadedUrls = await TravelStoriesService().uploadImages(
          filePaths,
        );

        if (uploadedUrls != null && uploadedUrls.isNotEmpty) {
          finalUrls.addAll(uploadedUrls);
        } else {
          finalUrls.addAll(filePaths); // fallback
        }
      } catch (e) {
        print('⚠️ Upload failed, submitting with local image paths: $e');
        finalUrls.addAll(_selectedImages.map((f) => f.path));
      }
    }

    // Dismiss loading spinner
    if (mounted) {
      Navigator.pop(context);
    }

    final authState = BlocProvider.of<AuthBloc>(context).state;
    String userId = '';
    String userName = 'Explorer';
    String userAvatar = '';

    if (authState is AuthAuthenticated) {
      userId = authState.user.id;
      userName = authState.user.displayName;
      if (userName.trim().isEmpty || userName.trim().toLowerCase() == 'anonymous') {
        userName = authState.user.email.isNotEmpty ? authState.user.email.split('@')[0] : 'Explorer';
      }
      userAvatar = authState.user.avatarUrl ?? '';
    }

    final newStory = TravelStory(
      id:
          widget.editStory?.id ??
          'story_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      locationName: location,
      category: _selectedCategory,
      description: description,
      imageUrl: finalUrls.isNotEmpty ? finalUrls.first : '',
      imageUrls: finalUrls,
      latitude: _selectedLatitude ?? widget.userLatitude,
      longitude: _selectedLongitude ?? widget.userLongitude,
      likesCount: widget.editStory?.likesCount ?? 0,
      comments: widget.editStory?.comments ?? [],
      createdAt: widget.editStory?.createdAt ?? DateTime.now(),
      isLiked: widget.editStory?.isLiked ?? false,
      isPublic: _isPublic,
      country: _selectedCountry,
      travelDate: _selectedTravelDate,
    );

    widget.onStorySubmitted(newStory);
    if (mounted) {
      Navigator.pop(context);
    }

    // Show success banner
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.brandGreen,
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              widget.editStory != null
                  ? 'Story updated!'
                  : 'Story shared to "$location"!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit =
        _locationController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty &&
        (_selectedImages.isNotEmpty || _existingImageUrls.isNotEmpty);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag Indicator
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Header
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 12),
              child: Row(
                children: [
                  Text(
                    'Share your travel story',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Privacy Toggle
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _isPublic = true),
                              child: Row(
                                children: [
                                  Icon(
                                    _isPublic
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Public',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => setState(() => _isPublic = false),
                              child: Row(
                                children: [
                                  Icon(
                                    !_isPublic
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Private',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Where was I? (Location)
                    const Text(
                      'Where was I? (Location Name)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _locationController,
                        textInputAction: TextInputAction.search,
                        onChanged: _onLocationChanged,
                        onSubmitted: (query) => _fetchSuggestions(query),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Diyaluma Falls, Koslanda',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13.5,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_isLoadingSuggestions)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.brandGreen,
                            ),
                          ),
                        ),
                      ),
                    if (_suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey[200]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                suggestion['description'] ?? '',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 12.5,
                                ),
                              ),
                              onTap: () => _selectSuggestion(suggestion),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 20),

                    // 2. Select Category
                    const Text(
                      'What was the location like?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final isSel = _selectedCategory == cat;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedCategory = cat),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSel ? Colors.black : Colors.grey[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSel
                                      ? Colors.black
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSel
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSel
                                        ? Colors.white
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Travel Date (When)
                    const Text(
                      'When did you visit? (Date)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedTravelDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppColors.brandGreen,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black87,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedTravelDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedTravelDate == null
                                  ? 'Choose Date'
                                  : "${_selectedTravelDate!.day}/${_selectedTravelDate!.month}/${_selectedTravelDate!.year}",
                              style: TextStyle(
                                fontSize: 13.5,
                                color: _selectedTravelDate == null ? Colors.grey[400] : Colors.black87,
                              ),
                            ),
                            const Icon(Icons.calendar_month, color: Colors.grey, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Country Selection
                    const Text(
                      'Select Country',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showCountryPickerSheet(
                          context,
                          selectedCountry: _selectedCountry,
                          includeGlobal: false,
                          title: 'Select Country',
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedCountry = picked;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedCountry ?? 'Select Country',
                              style: TextStyle(
                                color: _selectedCountry != null ? Colors.black87 : Colors.grey[400],
                                fontSize: 13.5,
                                fontWeight: _selectedCountry != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3. Story Comment
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Your Experience / Story',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        TextButton(
                          onPressed: () => FocusScope.of(context).unfocus(),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _descriptionController,
                        onChanged: (_) => setState(() {}),
                        maxLines: 4,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Share a brief comment or tell locals why this place stands out...',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 4. Attach Photograph
                    const Text(
                      'Add Photos',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedImages.isEmpty && _existingImageUrls.isEmpty)
                      GestureDetector(
                        onTap: _showImagePickerOptions,
                        child: Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              style: BorderStyle.solid,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_outlined,
                                size: 28,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to select multiple photos',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              _existingImageUrls.length +
                              _selectedImages.length +
                              1,
                          itemBuilder: (context, index) {
                            if (index ==
                                _existingImageUrls.length +
                                    _selectedImages.length) {
                              return GestureDetector(
                                onTap: _showImagePickerOptions,
                                child: Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.add,
                                      color: Colors.black54,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final isExisting =
                                index < _existingImageUrls.length;

                            return Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    isExisting
                                        ? Image.network(
                                            _existingImageUrls[index]
                                                    .startsWith('http')
                                                ? _existingImageUrls[index]
                                                : '${ApiConstants.baseUrl}${_existingImageUrls[index]}',
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                                  color: Colors.grey[200],
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color: Colors.grey,
                                                      size: 32,
                                                    ),
                                                  ),
                                                ),
                                          )
                                        : Image.file(
                                            _selectedImages[index -
                                                _existingImageUrls.length],
                                            fit: BoxFit.cover,
                                          ),
                                    Container(color: Colors.black12),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (isExisting) {
                                              _existingImageUrls.removeAt(
                                                index,
                                              );
                                            } else {
                                              _selectedImages.removeAt(
                                                index -
                                                    _existingImageUrls.length,
                                              );
                                            }
                                          });
                                        },
                                        child: const CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.black54,
                                          child: Icon(
                                            Icons.close,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 30),

                    // Submit Button
                    GestureDetector(
                      onTap: canSubmit ? _submit : null,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: canSubmit
                              ? AppColors.primaryGradient
                              : null,
                          color: canSubmit ? null : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: canSubmit
                                ? Colors.black12
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.editStory != null
                                ? 'Save Changes'
                                : 'Post Travel Story',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: canSubmit ? Colors.white : Colors.black26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
