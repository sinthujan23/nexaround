import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/google_places_service.dart';
import '../../data/models/travel_story.dart';
import '../../data/datasources/travel_stories_service.dart';

class PostStorySheet extends StatefulWidget {
  final Function(TravelStory) onStorySubmitted;
  final double userLatitude;
  final double userLongitude;

  const PostStorySheet({
    super.key,
    required this.onStorySubmitted,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  State<PostStorySheet> createState() => _PostStorySheetState();
}

class _PostStorySheetState extends State<PostStorySheet> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedCategory = '💎 Hidden Gem';
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  
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
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
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
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      print('⚠️ Error picking image: $e');
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
                leading: const Icon(Icons.photo_library, color: AppColors.brandGreen),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.brandGreen),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();

    if (location.isEmpty || description.isEmpty || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and attach a photo')),
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

    String imgUrl = _selectedImage!.path;
    try {
      final uploadedUrl = await TravelStoriesService().uploadImage(_selectedImage!.path);
      if (uploadedUrl != null) {
        imgUrl = uploadedUrl;
      }
    } catch (e) {
      print('⚠️ Upload failed, submitting with local image path: $e');
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
      userAvatar = authState.user.avatarUrl ?? '';
    }

    final newStory = TravelStory(
      id: 'story_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      locationName: location,
      category: _selectedCategory,
      description: description,
      imageUrl: imgUrl,
      likesCount: 0,
      comments: [],
      createdAt: DateTime.now(),
      isLiked: false,
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
              'Story shared to "$location"!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = _locationController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty &&
        _selectedImage != null;

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
            )
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Share Travel Story',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.black54, size: 22),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Where was I? (Location)
                  const Text(
                    'Where was I? (Location Name)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
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
                      onChanged: _onLocationChanged,
                      style: const TextStyle(color: Colors.black87, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. Diyaluma Falls, Koslanda',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandGreen),
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
                          )
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
                              style: const TextStyle(color: Colors.black87, fontSize: 12.5),
                            ),
                            onTap: () => _selectSuggestion(suggestion),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 20),

                  // 2. Select Category
                  const Text(
                    'Select Category',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
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
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? Colors.black : Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? Colors.black : Colors.grey[300]!,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                  color: isSel ? Colors.white : Colors.black54,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Story Comment
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Experience / Story',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
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
                      style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Share a brief comment or tell locals why this place stands out...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Attach Photograph
                  const Text(
                    'Attach Photograph',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
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
                      child: _selectedImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined, size: 28, color: Colors.grey[600]),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to capture or choose photo',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.cover,
                                  ),
                                  // Dark overlay
                                  Container(
                                    color: Colors.black12,
                                  ),
                                  // Delete / Close button
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedImage = null;
                                        });
                                      },
                                      child: const CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.black54,
                                        child: Icon(Icons.close, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                        gradient: canSubmit ? AppColors.primaryGradient : null,
                        color: canSubmit ? null : Colors.grey[200],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: canSubmit ? Colors.black12 : Colors.grey[300]!,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Post Travel Story',
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
