import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/forum_service.dart';
import '../../data/models/forum_category.dart';
import '../../data/models/forum_topic.dart';
import '../widgets/forum_topic_card.dart';
import '../widgets/create_topic_sheet.dart';

class ForumCategoryPage extends StatefulWidget {
  final ForumCategory category;

  const ForumCategoryPage({
    super.key,
    required this.category,
  });

  @override
  State<ForumCategoryPage> createState() => _ForumCategoryPageState();
}

class _ForumCategoryPageState extends State<ForumCategoryPage> {
  final ForumService _service = ForumService();
  final TextEditingController _searchController = TextEditingController();

  List<ForumTopic> _topics = [];
  bool _isLoading = true;
  final String _selectedSort = 'recent'; // 'recent', 'trending', 'unanswered'
  String? _selectedTagFilter;

  static const List<String> _quickFilters = [
    'All',
    'Hotels',
    'Food',
    'Transport',
    'Itinerary',
    'Safety',
  ];

  @override
  void initState() {
    super.initState();
    // Industry standard stale-while-revalidate: paint cached topics immediately
    final cached = _service.getCachedTopics(categorySlug: widget.category.slug);
    if (cached != null && cached.isNotEmpty) {
      _topics = cached;
      _isLoading = false;
    } else {
      _isLoading = true;
    }
    _loadTopics();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    if (_topics.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final list = await _service.getTopics(
        categorySlug: widget.category.slug,
        query: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        sortBy: _selectedSort,
        tag: _selectedTagFilter,
      );
      if (mounted) {
        setState(() {
          _topics = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openAskQuestion() async {
    final newTopic = await CreateTopicSheet.show(
      context,
      initialCategory: widget.category,
      availableCategories: [widget.category],
    );
    if (newTopic != null && mounted) {
      setState(() {
        _topics = [newTopic, ..._topics.where((t) => t.id != newTopic.id)];
      });
      _loadTopics();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Your question has been posted to the travel community!'),
          backgroundColor: AppColors.brandGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              backgroundColor: const Color(0xFF0F172A),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined, color: Colors.white),
                  tooltip: 'Ask a question',
                  onPressed: _openAskQuestion,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  '${widget.category.name} Forum',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.category.imageUrl != null && widget.category.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: widget.category.imageUrl!,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(color: const Color(0xFF0F172A)),
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.black.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 46,
                      child: Text(
                        widget.category.description ??
                            'Discuss itineraries, dining, accommodation, and safety with the community.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: RefreshIndicator(
          onRefresh: _loadTopics,
          color: AppColors.brandGreen,
          child: Column(
            children: [
              // Search & Filter Bar
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    // Search bar
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: (_) => _loadTopics(),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Search in ${widget.category.name}...',
                          hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadTopics();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick tag filters
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _quickFilters.map((filter) {
                          final isSelected = (_selectedTagFilter == null && filter == 'All') ||
                              (_selectedTagFilter == filter);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTagFilter = filter == 'All' ? null : filter;
                                });
                                _loadTopics();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  filter,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? Colors.white : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Topics Stream
              Expanded(
                child: (_isLoading && _topics.isEmpty)
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.brandGreen),
                      )
                    : _topics.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.question_answer_outlined,
                                  size: 48,
                                  color: Color(0xFFCBD5E1),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No topics in ${widget.category.name} yet',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Be the first traveler to start a discussion!',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _openAskQuestion,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Ask a Question'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandGreen,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                            itemCount: _topics.length,
                            itemBuilder: (context, index) {
                              return ForumTopicCard(
                                topic: _topics[index],
                                onTopicUpdated: _loadTopics,
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAskQuestion,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text(
          'Ask Question',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
