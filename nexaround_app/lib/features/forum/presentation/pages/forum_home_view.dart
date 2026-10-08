import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/countries.dart';
import '../../../../core/widgets/country_picker_sheet.dart';
import '../../data/datasources/forum_service.dart';
import '../../data/models/forum_category.dart';
import '../../data/models/forum_topic.dart';
import '../../data/models/forum_home_data.dart';
import '../widgets/forum_topic_card.dart';
import '../widgets/create_topic_sheet.dart';

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
  String? _selectedCountry;

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
    if (_homeData == null) {
      setState(() => _isLoading = true);
    }
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
      categories.addAll(_homeData!.travelTopics);
    }

    final newTopic = await CreateTopicSheet.show(
      context,
      availableCategories: categories,
      initialCountry: _selectedCountry,
    );

    if (newTopic != null && mounted) {
      // 1. Immediately insert into state at top of both recent and trending
      setState(() {
        if (_homeData != null) {
          _homeData = ForumHomeData(
            featuredDestinations: _homeData!.featuredDestinations,
            continentRegions: _homeData!.continentRegions,
            travelTopics: _homeData!.travelTopics,
            trendingTopics: [newTopic, ..._homeData!.trendingTopics.where((t) => t.id != newTopic.id)],
            recentTopics: [newTopic, ..._homeData!.recentTopics.where((t) => t.id != newTopic.id)],
          );
        }
        // Switch tab to recent so the new post is immediately shown to the user!
        _activeDiscussionTab = 'recent';

        // If a country filter was active that doesn't match this topic, clear it so it's guaranteed visible
        if (_selectedCountry != null && !_matchesCountry(newTopic, _selectedCountry!)) {
          _selectedCountry = null;
        }
      });

      _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Your question has been posted to the travel community!'),
          backgroundColor: AppColors.brandGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _countryFlag(String countryName) {
    final code = countryCodeFor(countryName);
    if (code == null || code.length != 2) return '🌐';
    final clean = code.toUpperCase();
    final first = clean.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = clean.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  bool _matchesCountry(ForumTopic topic, String countryName) {
    final query = countryName.toLowerCase().trim();
    final code = countryCodeFor(countryName)?.toLowerCase();

    // 1. Tags matching country name or ISO-2 code
    for (final tag in topic.tags) {
      final t = tag.toLowerCase().trim();
      if (t == query || (code != null && t == code) || t.contains(query)) {
        return true;
      }
    }

    // 2. Category matching
    if (topic.categoryName.toLowerCase().contains(query) ||
        topic.categorySlug.toLowerCase().contains(query)) {
      return true;
    }

    // 3. Title or content matching
    if (topic.title.toLowerCase().contains(query) ||
        topic.content.toLowerCase().contains(query)) {
      return true;
    }

    return false;
  }

  void _showCountryPicker() async {
    final picked = await showCountryPickerSheet(
      context,
      selectedCountry: _selectedCountry,
      includeGlobal: true,
      title: 'Filter Discussions by Country',
    );

    if (picked != null && mounted) {
      setState(() {
        if (picked == 'Global') {
          _selectedCountry = null;
        } else {
          _selectedCountry = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _homeData == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandGreen),
      );
    }

    final data = _homeData ?? const ForumHomeData();
    final List<ForumTopic> topicsToShow;

    if (_isSearching) {
      topicsToShow = _selectedCountry != null
          ? _filteredTopics.where((t) => _matchesCountry(t, _selectedCountry!)).toList()
          : _filteredTopics;
    } else {
      final currentList = _activeDiscussionTab == 'recent'
          ? data.recentTopics
          : data.trendingTopics;

      if (_selectedCountry != null) {
        final filtered = currentList.where((t) => _matchesCountry(t, _selectedCountry!)).toList();
        if (filtered.isNotEmpty) {
          topicsToShow = filtered;
        } else {
          // Check across both trending and recent topics so users don't miss topics
          final all = <ForumTopic>[...data.trendingTopics, ...data.recentTopics];
          final seen = <String>{};
          final unique = all.where((t) => seen.add(t.id)).toList();
          topicsToShow = unique.where((t) => _matchesCountry(t, _selectedCountry!)).toList();
        }
      } else {
        topicsToShow = currentList;
      }
    }

    final listWidget = ListView(
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // ── Hero Banner & Universal Search ────────────────────────────────
        _buildHeroHeader(),
        const SizedBox(height: 14),

        // ── Country Filter Bar ────────────────────────────────────────────
        _buildCountryFilterBar(),
        const SizedBox(height: 16),

        // ── Search Results (if user is actively typing in search) ─────────
        if (_isSearching) ...[
          Row(
            children: [
              Text(
                'Search Results (${topicsToShow.length})',
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
          if (topicsToShow.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              child: const Text(
                'No forum discussions matching your search.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            )
          else
            ...topicsToShow.map((t) => ForumTopicCard(topic: t, onTopicUpdated: _loadData)),
        ] else if (_selectedCountry != null) ...[
          // ── Selected Country Q&A View ───────────────────────────────────
          _buildSelectedCountryBanner(topicsToShow.length),
          const SizedBox(height: 16),

          _buildDiscussionsFeedHeader(),
          const SizedBox(height: 12),

          if (topicsToShow.isEmpty)
            _buildEmptyCountryState(_selectedCountry!)
          else
            ...topicsToShow.map((t) => ForumTopicCard(topic: t, onTopicUpdated: _loadData)),
        ] else ...[
          // ── Live Discussions Feed ───────────────────────────────────────
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: Image.asset(
                'assets/images/forum_banner_bg.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            // Cinematic dark gradient overlay for optimal text readability & showing landmarks
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFF0F172A).withValues(alpha: 0.90),
                      const Color(0xFF0F172A).withValues(alpha: 0.68),
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Card Content (compact vertical height)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppColors.brandGreen,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_rounded, size: 11.5, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'COMMUNITY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.9,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Travel Forums',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Ask questions, compare itineraries, and get tips from fellow travelers.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE2E8F0),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Universal Forum Search Bar
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        if (val.isEmpty) {
                          setState(() => _isSearching = false);
                        }
                      },
                      onSubmitted: _onSearch,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search destinations, hotels, tips...',
                        hintStyle: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white70),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white70),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _isSearching = false);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Primary "Ask a Question" Button
                  Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandGreen.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openAskQuestion,
                        borderRadius: BorderRadius.circular(12),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_comment_rounded, size: 16, color: Colors.white),
                            SizedBox(width: 7),
                            Text(
                              'Ask a Question',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryFilterBar() {
    final hasCountry = _selectedCountry != null && _selectedCountry!.isNotEmpty;
    final flag = hasCountry ? _countryFlag(_selectedCountry!) : '🌐';

    return GestureDetector(
      onTap: _showCountryPicker,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: hasCountry ? AppColors.brandGreen.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasCountry ? AppColors.brandGreen : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasCountry ? _selectedCountry! : 'All Countries',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: hasCountry ? AppColors.brandGreen : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (hasCountry)
              GestureDetector(
                onTap: () => setState(() => _selectedCountry = null),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.close_rounded, size: 18, color: AppColors.brandGreen),
                ),
              )
            else
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: Color(0xFF64748B),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedCountryBanner(int count) {
    final country = _selectedCountry ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreen.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _countryFlag(country),
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$country Discussions',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count advice topics & questions',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _selectedCountry = null),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close_rounded, size: 14),
                SizedBox(width: 4),
                Text('Clear', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCountryState(String country) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              _countryFlag(country),
              style: const TextStyle(fontSize: 36),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No discussions for $country yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Be the first traveler to ask for advice or share local tips about visiting $country.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _openAskQuestion,
            icon: const Icon(Icons.add_comment_rounded, size: 16),
            label: Text('Ask about $country'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ],
      ),
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
