import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/forum_service.dart';
import '../../data/models/forum_category.dart';
import '../../data/models/forum_topic.dart';
import '../../data/models/forum_home_data.dart';
import '../widgets/forum_topic_card.dart';
import '../widgets/create_topic_sheet.dart';
import 'forum_category_page.dart';

class ForumHomeView extends StatefulWidget {
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;

  const ForumHomeView({
    super.key,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
  });

  @override
  State<ForumHomeView> createState() => _ForumHomeViewState();
}

class _ForumHomeViewState extends State<ForumHomeView> {
  final ForumService _service = ForumService();
  final TextEditingController _searchController = TextEditingController();

  ForumHomeData? _homeData;
  bool _isLoading = true;
  String _activeDiscussionTab = 'trending'; // 'trending', 'recent', 'unanswered'

  List<ForumTopic> _filteredTopics = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getForumHome();
      if (mounted) {
        setState(() {
          _homeData = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredTopics = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _service.getTopics(query: q);
      if (mounted) {
        setState(() {
          _filteredTopics = results;
        });
      }
    } catch (_) {}
  }

  void _openAskQuestion() async {
    final categories = <ForumCategory>[];
    if (_homeData != null) {
      categories.addAll(_homeData!.featuredDestinations);
      categories.addAll(_homeData!.travelTopics);
    }

    final newTopic = await CreateTopicSheet.show(
      context,
      availableCategories: categories,
    );

    if (newTopic != null && mounted) {
      _loadData();
    }
  }

  void _openCategory(ForumCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForumCategoryPage(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _homeData == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandGreen),
      );
    }

    final data = _homeData ?? const ForumHomeData();
    final topicsToShow = _isSearching
        ? _filteredTopics
        : (_activeDiscussionTab == 'recent'
            ? data.recentTopics
            : data.trendingTopics);

    final listWidget = ListView(
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // ── Hero Banner & Search ──────────────────────────────────────────
        _buildHeroHeader(),
        const SizedBox(height: 16),

          // ── Search Results (if user is actively searching) ─────────────────
          if (_isSearching) ...[
            Row(
              children: [
                Text(
                  'Search Results (${_filteredTopics.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _isSearching = false);
                  },
                  child: const Text('Clear Search'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_filteredTopics.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 30),
                alignment: Alignment.center,
                child: const Text(
                  'No forum discussions matching your search.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              )
            else
              ..._filteredTopics.map((t) => ForumTopicCard(topic: t, onTopicUpdated: _loadData)),
          ] else ...[
            // ── Top Destinations Section ─────────────────────────────────────
            _buildSectionHeader(
              title: 'Top Destinations',
              subtitle: 'Popular global hubs with active traveler advice',
            ),
            const SizedBox(height: 10),
            _buildTopDestinationsCarousel(data.featuredDestinations),
            const SizedBox(height: 24),

            // ── Browse by Travel Topic / Style ────────────────────────────────
            _buildSectionHeader(
              title: 'Travel Topics',
              subtitle: 'Advice by trip style, flights, and backpacking hacks',
            ),
            const SizedBox(height: 10),
            _buildTravelTopicsGrid(data.travelTopics),
            const SizedBox(height: 24),

            // ── Continents & Regions Browser ──────────────────────────────────
            _buildSectionHeader(
              title: 'Destinations by Region',
              subtitle: 'Explore discussion hubs across world continents',
            ),
            const SizedBox(height: 10),
            _buildRegionsBrowser(data.continentRegions),
            const SizedBox(height: 28),

            // ── Active Discussions Feed ───────────────────────────────────────
            _buildDiscussionsFeedHeader(),
            const SizedBox(height: 12),

            if (topicsToShow.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                alignment: Alignment.center,
                child: const Text(
                  'No discussions found in this feed.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              )
            else
              ...topicsToShow.map((t) => ForumTopicCard(topic: t, onTopicUpdated: _loadData)),
          ],
        ],
    );

    if (widget.shrinkWrap) {
      return listWidget;
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.brandGreen,
      child: listWidget,
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'COMMUNITY',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'TripAdvisor-style Q&A',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Travel Forums',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ask questions, compare itineraries, and get tips from travelers who have been there.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // Universal Forum Search Bar
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                if (val.isEmpty) {
                  setState(() => _isSearching = false);
                }
              },
              onSubmitted: _onSearch,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search destinations, hotels, tips...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _isSearching = false);
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Primary "Ask a Question" Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _openAskQuestion,
              icon: const Icon(Icons.add_comment_rounded, size: 18),
              label: const Text(
                'Ask a Question',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildTopDestinationsCarousel(List<ForumCategory> destinations) {
    if (destinations.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: destinations.length,
        itemBuilder: (context, index) {
          final dest = destinations[index];
          return GestureDetector(
            onTap: () => _openCategory(dest),
            child: Container(
              width: 140,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (dest.imageUrl != null && dest.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: dest.imageUrl!,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(color: const Color(0xFF1E293B)),

                    // Dark gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),

                    // City name & topics badge
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dest.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 10,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${dest.topicsCount} topics',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTravelTopicsGrid(List<ForumCategory> topics) {
    if (topics.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.3,
      ),
      itemBuilder: (context, index) {
        final cat = topics[index];
        return GestureDetector(
          onTap: () => _openCategory(cat),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconForSlug(cat.slug),
                    size: 16,
                    color: AppColors.brandGreen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cat.topicsCount} questions',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconForSlug(String slug) {
    switch (slug) {
      case 'air-travel':
        return Icons.flight_takeoff_rounded;
      case 'solo-travel':
        return Icons.person_outline_rounded;
      case 'budget-backpacking':
        return Icons.account_balance_wallet_outlined;
      case 'family-travel':
        return Icons.family_restroom_outlined;
      case 'food-and-dining':
        return Icons.restaurant_outlined;
      case 'honeymoons-romance':
        return Icons.favorite_border_rounded;
      default:
        return Icons.explore_outlined;
    }
  }

  Widget _buildRegionsBrowser(List<ForumCategory> regions) {
    if (regions.isEmpty) return const SizedBox.shrink();

    return Column(
      children: regions.map((region) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.public_rounded, size: 18, color: Color(0xFF0F172A)),
              ),
              title: Text(
                region.name,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              subtitle: Text(
                '${region.subcategories.length} popular destination forums',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: region.subcategories.map((sub) {
                      return GestureDetector(
                        onTap: () => _openCategory(sub),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on_rounded, size: 13, color: AppColors.brandGreen),
                              const SizedBox(width: 4),
                              Text(
                                sub.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDiscussionsFeedHeader() {
    return Row(
      children: [
        const Text(
          'Live Discussions',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const Spacer(),
        // Segmented pill filter
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildFeedFilterTab('trending', '🔥 Trending'),
              _buildFeedFilterTab('recent', '🆕 Recent'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeedFilterTab(String key, String label) {
    final isSelected = _activeDiscussionTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeDiscussionTab = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
