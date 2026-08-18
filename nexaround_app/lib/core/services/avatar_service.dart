import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';

class AvatarPersona {
  final String id;
  final String style;
  final String name;
  final String title;
  final String subtitle;
  final String category;
  final String emoji;
  final String seed;
  final String bgHex;
  final List<Color> gradientColors;

  const AvatarPersona({
    required this.id,
    required this.style,
    required this.name,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.emoji,
    required this.seed,
    required this.bgHex,
    required this.gradientColors,
  });

  String get avatarUrl =>
      'https://api.dicebear.com/7.x/$style/png?seed=$seed&backgroundColor=$bgHex&radius=50&size=256';
}

class AvatarService {
  static const List<AvatarPersona> personas = [
    // Urban & Chic
    AvatarPersona(
      id: 'maya',
      style: 'lorelei',
      name: 'Maya',
      title: 'Urban Nomad',
      subtitle: 'City Vibes & Hidden Cafes',
      category: 'Urban',
      emoji: '📸',
      seed: 'Aneka',
      bgHex: 'ffd5dc',
      gradientColors: [Color(0xFFF857A6), Color(0xFFFF5858)],
    ),
    AvatarPersona(
      id: 'alex',
      style: 'lorelei',
      name: 'Alex',
      title: 'The Trailblazer',
      subtitle: 'Globe Trotter & Pathfinder',
      category: 'Urban',
      emoji: '🧭',
      seed: 'Felix',
      bgHex: 'b6e3f4',
      gradientColors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
    ),
    AvatarPersona(
      id: 'leo',
      style: 'avataaars',
      name: 'Leo',
      title: 'Street Scout',
      subtitle: 'Night Walks & Indie Spots',
      category: 'Urban',
      emoji: '🎧',
      seed: 'Leo',
      bgHex: 'c0aede',
      gradientColors: [Color(0xFF8A2387), Color(0xFFE94057)],
    ),
    AvatarPersona(
      id: 'liam',
      style: 'avataaars',
      name: 'Liam',
      title: 'Jet Voyager',
      subtitle: 'First-Class & Skylines',
      category: 'Urban',
      emoji: '✈️',
      seed: 'Liam',
      bgHex: 'd1d4f9',
      gradientColors: [Color(0xFF654EA3), Color(0xFFEAAFC8)],
    ),

    // Outdoor & Adventure
    AvatarPersona(
      id: 'kai',
      style: 'lorelei',
      name: 'Kai',
      title: 'Summit Trekker',
      subtitle: 'Alpine Peaks & Rugged Trails',
      category: 'Outdoor',
      emoji: '🧗',
      seed: 'Sawyer',
      bgHex: 'ffeaa7',
      gradientColors: [Color(0xFFF7971E), Color(0xFFFFD200)],
    ),
    AvatarPersona(
      id: 'elena',
      style: 'lorelei',
      name: 'Elena',
      title: 'Coastal Wanderer',
      subtitle: 'Sunsets, Ocean & Waves',
      category: 'Outdoor',
      emoji: '🏄',
      seed: 'Eden',
      bgHex: 'c1f0c1',
      gradientColors: [Color(0xFF11998E), Color(0xFF38EF7D)],
    ),
    AvatarPersona(
      id: 'chloe',
      style: 'lorelei',
      name: 'Chloe',
      title: 'Eco Explorer',
      subtitle: 'Serene Forests & Nature',
      category: 'Outdoor',
      emoji: '🌿',
      seed: 'Chloe',
      bgHex: 'cbf3f0',
      gradientColors: [Color(0xFF134E5E), Color(0xFF71B280)],
    ),
    AvatarPersona(
      id: 'aria',
      style: 'lorelei',
      name: 'Aria',
      title: 'Night Stargazer',
      subtitle: 'Campfires & Midnight Skies',
      category: 'Outdoor',
      emoji: '🌌',
      seed: 'Amaya',
      bgHex: 'dcdde1',
      gradientColors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    ),

    // Culture & Food
    AvatarPersona(
      id: 'sophia',
      style: 'lorelei',
      name: 'Sophia',
      title: 'Gourmet Voyager',
      subtitle: 'Street Bites & Michelin Flavors',
      category: 'Culture',
      emoji: '🍜',
      seed: 'Sophia',
      bgHex: 'fed7aa',
      gradientColors: [Color(0xFFFF9966), Color(0xFFFF5E62)],
    ),
    AvatarPersona(
      id: 'julian',
      style: 'micah',
      name: 'Julian',
      title: 'Heritage Curator',
      subtitle: 'Architecture & Fine Arts',
      category: 'Culture',
      emoji: '🏛️',
      seed: 'Julian',
      bgHex: 'd0e1fd',
      gradientColors: [Color(0xFF4B6CB7), Color(0xFF182848)],
    ),
    AvatarPersona(
      id: 'noah',
      style: 'micah',
      name: 'Noah',
      title: 'Zen Minimalist',
      subtitle: 'Mindful Travel & Quiet Escapes',
      category: 'Culture',
      emoji: '🗺️',
      seed: 'Noah',
      bgHex: 'e2e8f0',
      gradientColors: [Color(0xFF3A6073), Color(0xFF3A7BD5)],
    ),

    // Cyber & AI
    AvatarPersona(
      id: 'neva_bot',
      style: 'bottts',
      name: 'NEVA Scout',
      title: 'AI Companion',
      subtitle: 'Quantum Intelligence Pathfinder',
      category: 'Cyber',
      emoji: '🤖',
      seed: 'NevaCompanion99',
      bgHex: 'e0c3fc',
      gradientColors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
    ),
  ];

  static AvatarPersona getPersonaById(String? id) {
    if (id == null) return personas.first;
    return personas.firstWhere(
      (p) => p.id == id,
      orElse: () => personas.first,
    );
  }

  /// Opens the Avatar Studio bottom sheet
  static void showAvatarStudio(BuildContext context, UserEntity user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AvatarStudioSheet(user: user),
    );
  }
}

class UserAvatarView extends StatelessWidget {
  final UserEntity? user;
  final double size;
  final bool showEditBadge;
  final VoidCallback? onTap;

  const UserAvatarView({
    super.key,
    required this.user,
    this.size = 100,
    this.showEditBadge = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String name = user?.displayName ?? '';
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .where((String e) => e.isNotEmpty)
            .map((String e) => e[0])
            .take(2)
            .join('')
            .toUpperCase()
        : '??';

    final avatarUrl = user?.avatarUrl;
    final hasSocialPhoto = avatarUrl != null && avatarUrl.trim().isNotEmpty;

    return AnimatedBuilder(
      animation: Listenable.merge([
        CacheService.selectedAvatarNotifier,
        CacheService.useSocialAvatarNotifier,
      ]),
      builder: (context, _) {
        final useSocial = CacheService.getUseSocialAvatar() && hasSocialPhoto;
        final selectedId = CacheService.getSelectedAvatarId();
        final persona = AvatarService.getPersonaById(selectedId);

        Widget avatarContent;

        if (useSocial) {
          avatarContent = CachedNetworkImage(
            imageUrl: avatarUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (context, url, error) => _buildPersonaFallback(persona, initials),
          );
        } else if (selectedId != null || !hasSocialPhoto) {
          avatarContent = CachedNetworkImage(
            imageUrl: persona.avatarUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: persona.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  persona.emoji,
                  style: TextStyle(fontSize: size * 0.4),
                ),
              ),
            ),
            errorWidget: (context, url, error) => _buildPersonaFallback(persona, initials),
          );
        } else {
          avatarContent = _buildPersonaFallback(persona, initials);
        }

        return GestureDetector(
          onTap: onTap ??
              (showEditBadge && user != null
                  ? () => AvatarService.showAvatarStudio(context, user!)
                  : null),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: useSocial
                        ? [AppColors.primary, AppColors.brandGreen]
                        : persona.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (useSocial
                              ? AppColors.primary
                              : persona.gradientColors.first)
                          .withValues(alpha: 0.35),
                      blurRadius: size * 0.24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(size),
                    child: Container(
                      color: Colors.white,
                      child: avatarContent,
                    ),
                  ),
                ),
              ),
              if (showEditBadge)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: size * 0.32,
                    height: size * 0.32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceElevated,
                      border: Border.all(
                        color: AppColors.primary,
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.primary,
                      size: size * 0.16,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPersonaFallback(AvatarPersona persona, String initials) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: persona.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          persona.emoji.isNotEmpty ? persona.emoji : initials,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _AvatarStudioSheet extends StatefulWidget {
  final UserEntity user;
  const _AvatarStudioSheet({required this.user});

  @override
  State<_AvatarStudioSheet> createState() => _AvatarStudioSheetState();
}

class _AvatarStudioSheetState extends State<_AvatarStudioSheet> {
  late bool _useSocial;
  late String? _selectedId;
  String _selectedCategory = 'All';

  final List<String> _categories = ['All', 'Urban', 'Outdoor', 'Culture', 'Cyber'];

  @override
  void initState() {
    super.initState();
    _useSocial = CacheService.getUseSocialAvatar();
    _selectedId = CacheService.getSelectedAvatarId() ?? AvatarService.personas.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final socialUrl = widget.user.avatarUrl;
    final hasSocialPhoto = socialUrl != null && socialUrl.trim().isNotEmpty;
    final activePersona = AvatarService.getPersonaById(_selectedId);

    final filteredPersonas = _selectedCategory == 'All'
        ? AvatarService.personas
        : AvatarService.personas
            .where((p) => p.category == _selectedCategory)
            .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 36,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Avatar Studio',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Select your modern traveler persona',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceVariant,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Live Selected Banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _useSocial
                    ? [
                        AppColors.primary.withValues(alpha: 0.12),
                        AppColors.brandGreen.withValues(alpha: 0.08),
                      ]
                    : [
                        activePersona.gradientColors.first.withValues(alpha: 0.14),
                        activePersona.gradientColors.last.withValues(alpha: 0.06),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _useSocial
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : activePersona.gradientColors.first.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _useSocial
                          ? [AppColors.primary, AppColors.brandGreen]
                          : activePersona.gradientColors,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48),
                      child: Container(
                        color: Colors.white,
                        child: _useSocial && hasSocialPhoto
                            ? CachedNetworkImage(
                                imageUrl: socialUrl,
                                fit: BoxFit.cover,
                              )
                            : CachedNetworkImage(
                                imageUrl: activePersona.avatarUrl,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _useSocial ? 'Google / Apple Photo' : activePersona.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _useSocial ? '🌐' : activePersona.emoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _useSocial
                            ? 'Using your connected account photo'
                            : '${activePersona.title} • ${activePersona.subtitle}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (_useSocial
                            ? AppColors.primary
                            : activePersona.gradientColors.first)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _useSocial
                          ? AppColors.primary
                          : activePersona.gradientColors.first,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Filter Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedCategory = cat);
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Social photo tile if available
                if (hasSocialPhoto && _selectedCategory == 'All') ...[
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _useSocial = true;
                      });
                      await CacheService.setUseSocialAvatar(true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _useSocial
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _useSocial ? AppColors.primary : AppColors.border,
                          width: _useSocial ? 2.0 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: CachedNetworkImage(
                              imageUrl: socialUrl,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Google / Apple Profile Photo',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Use linked account profile picture',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_useSocial)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Grid of Personas
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.06,
                  ),
                  itemCount: filteredPersonas.length,
                  itemBuilder: (context, index) {
                    final persona = filteredPersonas[index];
                    final isSelected = !_useSocial && _selectedId == persona.id;

                    return GestureDetector(
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _useSocial = false;
                          _selectedId = persona.id;
                        });
                        await CacheService.setUseSocialAvatar(false);
                        await CacheService.setSelectedAvatarId(persona.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? persona.gradientColors.first.withValues(alpha: 0.1)
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isSelected
                                ? persona.gradientColors.first
                                : AppColors.border,
                            width: isSelected ? 2.2 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: persona.gradientColors.first
                                        .withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: persona.gradientColors,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: persona.gradientColors.first
                                              .withValues(alpha: 0.25),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(60),
                                        child: Container(
                                          color: Colors.white,
                                          child: CachedNetworkImage(
                                            imageUrl: persona.avatarUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Center(
                                              child: Text(
                                                persona.emoji,
                                                style: const TextStyle(fontSize: 26),
                                              ),
                                            ),
                                            errorWidget: (_, __, ___) => Center(
                                              child: Text(
                                                persona.emoji,
                                                style: const TextStyle(fontSize: 26),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(3.5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: persona.gradientColors.first,
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${persona.name} • ${persona.title}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                persona.subtitle,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
