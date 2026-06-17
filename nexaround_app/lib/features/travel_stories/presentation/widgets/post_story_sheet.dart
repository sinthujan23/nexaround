import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  String? _selectedImageUrl;
  
  final List<String> _categories = [
    '💎 Hidden Gem',
    '🧭 Offbeat Place',
    '🤫 Local Secret',
    '🌅 Scenic Viewpoint',
    '🍔 Food Spot',
  ];

  late List<Map<String, String>> _presets;

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
    _presets = TravelStoriesService.getPresetPhotos();
    // Pre-select first image
    if (_presets.isNotEmpty) {
      _selectedImageUrl = _presets.first['url'];
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();
    final imgUrl = _selectedImageUrl;

    if (location.isEmpty || description.isEmpty || imgUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a photo')),
      );
      return;
    }

    final newStory = TravelStory(
      id: 'story_${DateTime.now().millisecondsSinceEpoch}',
      userName: 'You @explorer_me',
      userAvatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&auto=format&fit=crop',
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
    Navigator.pop(context);
    
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
        _selectedImageUrl != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1018).withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            children: [
              // Drag Indicator
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
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
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Where was I? (Location)
                      const Text(
                        'Where was I? (Location Name)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: TextField(
                          controller: _locationController,
                          onChanged: _onLocationChanged,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'e.g. Diyaluma Falls, Koslanda',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.5),
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
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
                            ),
                          ),
                        ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
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
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
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
                                  color: isSel ? Colors.white : Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSel ? Colors.white : Colors.white.withOpacity(0.12),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    cat,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                      color: isSel ? const Color(0xFF0A1018) : Colors.white70,
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
                      const Text(
                        'Your Experience / Story',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: TextField(
                          controller: _descriptionController,
                          onChanged: (_) => setState(() {}),
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                          decoration: InputDecoration(
                            hintText: 'Share a brief comment or tell locals why this place stands out...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 4. Post Photo
                      const Text(
                        'Attach Photograph',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _presets.length,
                          itemBuilder: (context, index) {
                            final preset = _presets[index];
                            final url = preset['url']!;
                            final title = preset['title']!;
                            final isSel = _selectedImageUrl == url;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedImageUrl = url),
                              child: Container(
                                width: 140,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSel ? Colors.white : Colors.white10,
                                    width: isSel ? 2.5 : 1,
                                  ),
                                  boxShadow: isSel
                                      ? [
                                          BoxShadow(
                                            color: Colors.white.withOpacity(0.25),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.cover,
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 8,
                                        left: 8,
                                        right: 8,
                                        child: Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSel)
                                        const Positioned(
                                          top: 8,
                                          right: 8,
                                          child: CircleAvatar(
                                            radius: 10,
                                            backgroundColor: Colors.white,
                                            child: Icon(Icons.check, size: 12, color: Color(0xFF0A1018)),
                                          ),
                                        ),
                                    ],
                                  ),
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
                            gradient: canSubmit ? AppColors.primaryGradient : null,
                            color: canSubmit ? null : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: canSubmit ? Colors.white.withOpacity(0.15) : Colors.white10,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Post Travel Story',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: canSubmit ? Colors.white : Colors.white38,
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
      ),
    );
  }
}
