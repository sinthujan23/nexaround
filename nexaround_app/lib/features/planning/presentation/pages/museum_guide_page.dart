import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/planning/data/museum_repository.dart';
import 'package:nexaround_app/features/planning/domain/museum.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Displays a curated, time-filtered itinerary for a single museum.
///
/// The user picks a duration (5 Hours / 1 Day / 2 Days) and sees the
/// masterpieces grouped by building in a beautiful vertical timeline.
class MuseumGuidePage extends StatefulWidget {
  final MuseumListItem museum;

  const MuseumGuidePage({super.key, required this.museum});

  @override
  State<MuseumGuidePage> createState() => _MuseumGuidePageState();
}

class _MuseumGuidePageState extends State<MuseumGuidePage> {
  final _repo = MuseumRepository();

  List<String> _durations = ['5h', '1d', '2d'];
  static const _durationLabels = {'5h': '5 Hours', '1d': '1 Day', '2d': '2 Days'};

  static const Map<String, _MuseumExtraInfo> _extraInfo = {
    'louvre': _MuseumExtraInfo(
      website: 'https://www.louvre.fr/en',
      hours: '9am–6pm (Closed Tue)',
    ),
    'national-museum-of-china': _MuseumExtraInfo(
      website: 'http://en.chnmuseum.cn/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'vatican-museums': _MuseumExtraInfo(
      website: 'https://www.museivaticani.va',
      hours: '8am–7pm (Closed Sun)',
    ),
    'grand-egyptian-museum': _MuseumExtraInfo(
      website: 'https://gem.eg/',
      hours: '09:00 AM–06:00 PM (Open Daily)',
    ),
    'national-museum-of-korea': _MuseumExtraInfo(
      website: 'https://www.museum.go.kr/ENG/contents/E0101010000.do',
      hours: 'Mon/Tue/Thu/Fri/Sun: 9:30 am – 5:30 pm, Wed/Sat: 9:30 am – 9:00 pm',
    ),
    'british-museum': _MuseumExtraInfo(
      website: 'https://www.britishmuseum.org',
      hours: '10am–5pm (Fri until 8:30pm)',
    ),
    'china-science-and-technology-museum': _MuseumExtraInfo(
      website: 'http://www.cstm.org.cn/',
      hours: '9:30am–5pm (Closed Mon)',
    ),
    'natural-history-museum-south-kensington': _MuseumExtraInfo(
      website: 'https://www.nhm.ac.uk',
      hours: '10am–5:50pm',
    ),
    'metropolitan-museum-of-art': _MuseumExtraInfo(
      website: 'https://www.metmuseum.org',
      hours: '10am–5pm (Fri/Sat until 9pm, Closed Wed)',
    ),
    'nanjing-museum': _MuseumExtraInfo(
      website: 'http://www.njmuseum.com/en',
      hours: '9am–5pm (Closed Mon)',
    ),
    'american-museum-of-natural-history': _MuseumExtraInfo(
      website: 'https://www.amnh.org',
      hours: '10am–5:30pm',
    ),
    'tate-modern': _MuseumExtraInfo(
      website: 'https://www.tate.org.uk/visit/tate-modern',
      hours: '10am–6pm',
    ),
    'hubei-provincial-museum': _MuseumExtraInfo(
      website: 'http://www.hbmus.org/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'shanghai-museum-east': _MuseumExtraInfo(
      website: 'https://www.shanghaimuseum.net/',
      hours: '9am–5pm (Closed Tue)',
    ),
    'national-gallery-of-art': _MuseumExtraInfo(
      website: 'https://www.nga.gov',
      hours: '10am–5pm',
    ),
    'musee-dorsay': _MuseumExtraInfo(
      website: 'https://www.musee-orsay.fr/en',
      hours: '9:30am–6pm (Thu until 9:45pm, Closed Mon)',
    ),
    'national-museum-of-anthropology': _MuseumExtraInfo(
      website: 'https://mna.inah.gob.mx/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'state-russian-museum': _MuseumExtraInfo(
      website: 'http://www.rusmuseum.ru/en/',
      hours: '10am–6pm (Mon until 8pm, Thu until 9pm, Closed Tue)',
    ),
    'state-hermitage-museum': _MuseumExtraInfo(
      website: 'https://www.hermitagemuseum.org',
      hours: '11am–6pm (Thu/Sat until 8pm, Closed Mon)',
    ),
    'victoria-and-albert-museum': _MuseumExtraInfo(
      website: 'https://www.vam.ac.uk',
      hours: '10am–5:45pm (Fri until 10pm)',
    ),
    'prado-museum': _MuseumExtraInfo(
      website: 'https://www.museodelprado.es/en',
      hours: '10am–8pm (Sun/Holidays 10am–7pm)',
    ),
    'centre-pompidou': _MuseumExtraInfo(
      website: 'https://www.centrepompidou.fr/en',
      hours: '11am–9pm (Closed Tue)',
    ),
    'national-gallery': _MuseumExtraInfo(
      website: 'https://www.nationalgallery.org.uk',
      hours: '10am–6pm (Fri until 9pm)',
    ),
    'musee-national-dhistoire-naturelle': _MuseumExtraInfo(
      website: 'https://www.mnhn.fr/en',
      hours: '10am–6pm (Closed Tue)',
    ),
    'national-air-and-space-museum': _MuseumExtraInfo(
      website: 'https://airandspace.si.edu',
      hours: '10am–5:30pm',
    ),
    'mevlana-museum': _MuseumExtraInfo(
      website: 'https://www.muze.gov.tr',
      hours: '9am–5:30pm',
    ),
    'national-museum-of-natural-history': _MuseumExtraInfo(
      website: 'https://naturalhistory.si.edu',
      hours: '10am–5:30pm',
    ),
    'galleria-degli-uffizi': _MuseumExtraInfo(
      website: 'https://www.uffizi.it/en',
      hours: '8:15am–6:30pm (Closed Mon)',
    ),
    'national-museum-of-natural-science': _MuseumExtraInfo(
      website: 'https://www.nmns.edu.tw',
      hours: '9am–5pm (Closed Mon)',
    ),
    'science-museum': _MuseumExtraInfo(
      website: 'https://www.sciencemuseum.org.uk',
      hours: '10am–6pm',
    ),
    'museum-of-modern-art': _MuseumExtraInfo(
      website: 'https://www.moma.org',
      hours: '10:30am–5:30pm (Sat until 7pm)',
    ),
    'national-museum-of-nature-and-science': _MuseumExtraInfo(
      website: 'https://www.kahaku.go.jp/english/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'm-plus': _MuseumExtraInfo(
      website: 'https://www.mplus.org.hk',
      hours: '10am–6pm (Fri until 10pm, Closed Mon)',
    ),
    'state-tretyakov-gallery': _MuseumExtraInfo(
      website: 'https://www.tretyakovgallery.ru/en/',
      hours: '10am–6pm (Thu/Fri/Sat/Sun until 9pm, Closed Mon)',
    ),
    'rijksmuseum': _MuseumExtraInfo(
      website: 'https://www.rijksmuseum.nl/en',
      hours: '9am–5pm',
    ),
    'tokyo-national-museum': _MuseumExtraInfo(
      website: 'https://www.tnm.jp',
      hours: '9:30am–5pm (Closed Mon)',
    ),
    'art-gallery-of-new-south-wales': _MuseumExtraInfo(
      website: 'https://www.artgallery.nsw.gov.au',
      hours: '10am–5pm (Wed until 10pm)',
    ),
    'national-museum-of-scotland': _MuseumExtraInfo(
      website: 'https://www.nms.ac.uk',
      hours: '10am–5pm',
    ),
    'royal-museums-greenwich': _MuseumExtraInfo(
      website: 'https://www.rmg.co.uk',
      hours: '10am–5pm',
    ),
    'galleria-dellaccademia': _MuseumExtraInfo(
      website: 'https://www.galleriaaccademiafirenze.it/en/',
      hours: '8:15am–6:50pm (Closed Mon)',
    ),
    'smithsonian-museum-of-american-history': _MuseumExtraInfo(
      website: 'https://americanhistory.si.edu',
      hours: '10am–5:30pm',
    ),
    'national-gallery-singapore': _MuseumExtraInfo(
      website: 'https://www.nationalgallery.sg',
      hours: '10am–7pm',
    ),
    '21st-century-museum-of-contemporary-art': _MuseumExtraInfo(
      website: 'https://www.kanazawa21.jp',
      hours: '10am–6pm (Fri/Sat until 8pm, Closed Mon)',
    ),
    'national-science-and-technology-museum': _MuseumExtraInfo(
      website: 'https://www.nstm.gov.tw',
      hours: '9am–5pm (Closed Mon)',
    ),
    'national-palace-museum': _MuseumExtraInfo(
      website: 'https://www.npm.gov.tw',
      hours: '9am–5pm (Closed Mon)',
    ),
    'national-museum-in-krakow': _MuseumExtraInfo(
      website: 'https://mnk.pl',
      hours: '10am–6pm (Sun 10am–4pm, Closed Mon)',
    ),
    'van-gogh-museum': _MuseumExtraInfo(
      website: 'https://www.vangoghmuseum.nl/en',
      hours: '9am–6pm',
    ),
    'the-national-art-center-tokyo': _MuseumExtraInfo(
      website: 'https://www.nact.jp/english/',
      hours: '10am–6pm (Fri/Sat until 8pm, Closed Tue)',
    ),
    'california-science-center': _MuseumExtraInfo(
      website: 'https://californiasciencecenter.org',
      hours: '10am–5pm',
    ),
    'china-national-silk-museum': _MuseumExtraInfo(
      website: 'http://en.chinasilkmuseum.com/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'kunsthistorisches-museum': _MuseumExtraInfo(
      website: 'https://www.khm.at/en/',
      hours: '10am–6pm (Thu until 9pm, Closed Mon)',
    ),
    'fujian-museum': _MuseumExtraInfo(
      website: 'http://www.fjmuseum.com/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'hangzhou-arts-and-crafts-museum': _MuseumExtraInfo(
      website: 'http://www.hzacm.com/',
      hours: '9am–4:30pm (Closed Mon)',
    ),
    'national-gallery-of-victoria': _MuseumExtraInfo(
      website: 'https://www.ngv.vic.gov.au',
      hours: '10am–5pm',
    ),
    'national-museum-in-warsaw': _MuseumExtraInfo(
      website: 'https://www.mnw.art.pl/en/',
      hours: '10am–6pm (Fri until 8pm, Closed Mon)',
    ),
    'louis-vuitton-foundation': _MuseumExtraInfo(
      website: 'https://www.fondationlouisvuitton.fr/en',
      hours: '11am–8pm (Closed Tue)',
    ),
    'kaohsiung-museum-of-fine-arts': _MuseumExtraInfo(
      website: 'https://www.kmfa.gov.tw',
      hours: '9:30am–5:30pm (Closed Mon)',
    ),
    'acropolis-museum': _MuseumExtraInfo(
      website: 'https://www.theacropolismuseum.gr/en',
      hours: '9am–5pm (Mon until 4pm, Fri until 10pm)',
    ),
    'centro-cultural-banco-do-brasil': _MuseumExtraInfo(
      website: 'https://ccbb.com.br',
      hours: '9am–9pm (Closed Tue)',
    ),
    'palacio-de-cristal-del-retiro': _MuseumExtraInfo(
      website: 'https://www.museoreinasofia.es',
      hours: '10am–10pm',
    ),
    'guggenheim-museum-bilbao': _MuseumExtraInfo(
      website: 'https://www.guggenheim-bilbao.eus/en',
      hours: '10am–7pm (Closed Mon)',
    ),
    'chinese-aviation-museum': _MuseumExtraInfo(
      website: 'http://www.chn-am.com/',
      hours: '9am–5pm (Closed Mon)',
    ),
    'moscow-kremlin-museum': _MuseumExtraInfo(
      website: 'https://www.kreml.ru/en-US/',
      hours: '10am–5pm (Closed Thu)',
    ),
  };

  _MuseumExtraInfo get _museumExtra {
    return _extraInfo[widget.museum.slug] ??
        _MuseumExtraInfo(
          website: 'https://www.google.com/search?q=${Uri.encodeComponent(widget.museum.name)}',
          hours: '9:00 AM – 6:00 PM',
        );
  }

  String _selected = '1d';
  MuseumItinerary? _itinerary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _fetch();
  }

  void _calculateAvailableDurations(List<Masterpiece> masterpieces) {
    final has5h = masterpieces.any((m) => m.included5h);
    final has1d = masterpieces.any((m) => m.included1d);
    final has2d = masterpieces.any((m) => m.included2d);
    
    final list = <String>[];
    if (has5h) list.add('5h');
    if (has1d) list.add('1d');
    if (has2d) list.add('2d');
    
    if (list.isNotEmpty) {
      setState(() {
        _durations = list;
        if (!list.contains(_selected)) {
          _selected = list.contains('1d') ? '1d' : list.first;
        }
      });
    }
  }

  void _loadCache() {
    // Try to load cached museum detail for durations check
    final detail = _repo.getCachedMuseumDetail(widget.museum.slug);
    if (detail != null) {
      _calculateAvailableDurations(detail.masterpieces);
    }

    // Load cached itinerary
    final cached = _repo.getCachedItinerary(
      slug: widget.museum.slug,
      duration: _selected,
    );
    if (cached != null) {
      _itinerary = cached;
      _loading = false;
    }
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = _itinerary == null;
      _error = null;
    });
    try {
      // 1. Fetch fresh museum details first to ensure correct durations check
      final detail = await _repo.getMuseumDetail(widget.museum.slug);
      _calculateAvailableDurations(detail.masterpieces);

      // 2. Fetch fresh itinerary
      final it = await _repo.getItinerary(
        slug: widget.museum.slug,
        duration: _selected,
      );
      if (!mounted) return;
      setState(() {
        _itinerary = it;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_itinerary == null) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ── Category → color mapping ─────────────────────────────────────────────
  Color _categoryColor(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('imperial')) return const Color(0xFFDAA520);
    if (lower.contains('renaissance')) return const Color(0xFF1565C0);
    if (lower.contains('sculpture')) return const Color(0xFF6D4C41);
    if (lower.contains('antiquit')) return const Color(0xFFBF360C);
    if (lower.contains('dutch') || lower.contains('flemish')) {
      return const Color(0xFFE65100);
    }
    if (lower.contains('impressioni')) return const Color(0xFF7B1FA2);
    if (lower.contains('modern') || lower.contains('cubism')) {
      return const Color(0xFF00897B);
    }
    if (lower.contains('baroque')) return const Color(0xFF880E4F);
    if (lower.contains('decorative')) return const Color(0xFF00838F);
    if (lower.contains('french')) return const Color(0xFF283593);
    if (lower.contains('spanish')) return const Color(0xFFC62828);
    if (lower.contains('british') || lower.contains('german')) {
      return const Color(0xFF37474F);
    }
    if (lower.contains('treasury')) return const Color(0xFFFF8F00);
    if (lower.contains('architect')) return const Color(0xFF558B2F);
    if (lower.contains('arms')) return const Color(0xFF455A64);
    return AppColors.brandGreen;
  }

  IconData _categoryIcon(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('imperial')) return Icons.castle_rounded;
    if (lower.contains('sculpture')) return Icons.accessibility_new_rounded;
    if (lower.contains('antiquit')) return Icons.temple_hindu_rounded;
    if (lower.contains('decorative')) return Icons.diamond_rounded;
    if (lower.contains('arms')) return Icons.shield_rounded;
    if (lower.contains('treasury')) return Icons.lock_rounded;
    if (lower.contains('architect')) return Icons.architecture_rounded;
    return Icons.palette_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.museum.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.museum.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: widget.museum.imageUrl!.startsWith('/')
                          ? '${ApiConstants.baseUrl}${widget.museum.imageUrl}'
                          : widget.museum.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.charcoal,
                        child: const Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.brandGreen,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.charcoal,
                        child: const Icon(Icons.museum_rounded,
                            color: Colors.white38, size: 80),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.charcoal,
                      child: const Icon(Icons.museum_rounded,
                          color: Colors.white38, size: 80),
                    ),
                  // Gradient scrim
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  // City / Country label
                  Positioned(
                    left: 16,
                    bottom: 56,
                    child: Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.museum.city}, ${widget.museum.country}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Sticky Duration Selector ─────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _DurationHeaderDelegate(
              selected: _selected,
              onChanged: (d) {
                setState(() => _selected = d);
                _fetch();
              },
              labels: _durationLabels,
              durations: _durations,
            ),
          ),

          // ── Ticket Banner ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Material(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    // Open ticket URL or a generic search
                    final url = 'https://www.getyourguide.com/s/?q=${Uri.encodeComponent(widget.museum.name)}';
                    launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.brandGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.confirmation_num_rounded,
                              color: AppColors.brandGreen, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Skip-the-Line Tickets',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Book fast-track entry & guided tours',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white38, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Stats Row ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _statChip(
                        Icons.visibility_rounded,
                        _itinerary != null
                            ? '${_itinerary!.totalItems} Must-See'
                            : '…',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statChip(
                          Icons.access_time_filled_rounded,
                          _museumExtra.hours,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      launchUrl(
                        Uri.parse(_museumExtra.website),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.language_rounded,
                              size: 16, color: AppColors.brandGreen),
                          const SizedBox(width: 6),
                          Text(
                            'Visit official website',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandGreen,
                              decoration: TextDecoration.underline,
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

          // ── Content ──────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brandGreen),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _fetch,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_itinerary != null) ...[
            SliverToBoxAdapter(
              child: _buildDisclaimerCard(),
            ),
            ..._buildTimeline(_itinerary!),
          ],

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Timeline builder ──────────────────────────────────────────────────────

  List<Widget> _buildTimeline(MuseumItinerary itinerary) {
    final slivers = <Widget>[];
    for (int bi = 0; bi < itinerary.buildings.length; bi++) {
      final section = itinerary.buildings[bi];
      // Building header
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.domain_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.building,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${section.items.length} stops',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));

      // Items as timeline cards
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final mp = section.items[index];
            final isFirst = index == 0;
            final isLast = index == section.items.length - 1;
            final color = _categoryColor(mp.category);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Timeline rail ──
                    SizedBox(
                      width: 36,
                      child: Column(
                        children: [
                          if (!isFirst)
                            Expanded(child: Container(width: 2, color: color.withOpacity(0.3)))
                          else
                            const Expanded(child: SizedBox()),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: color.withOpacity(0.3),
                                    blurRadius: 6),
                              ],
                            ),
                          ),
                          if (!isLast)
                            Expanded(child: Container(width: 2, color: color.withOpacity(0.3)))
                          else
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                    ),
                    // ── Card ──
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x08000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: rank + category badge
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_categoryIcon(mp.category),
                                            size: 12, color: color),
                                        const SizedBox(width: 4),
                                        Text(
                                          mp.category,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '#${mp.rank}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Title
                              Text(
                                mp.mustSeeItem,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              if (mp.artist != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  mp.artist!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              // Room
                              Row(
                                children: [
                                  const Icon(Icons.room_rounded,
                                      size: 12,
                                      color: AppColors.textTertiary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      mp.roomGallery,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (mp.description != null &&
                                  mp.description!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  mp.description!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: section.items.length,
        ),
      ));
    }
    return slivers;
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.brandGreen,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Disclaimer',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "This itinerary is intended as a guide only. Gallery layouts, room numbers, exhibits, and visitor routes may change without notice. Please check the museum's official website for the latest updates before your visit.",
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky duration header delegate ─────────────────────────────────────────

class _DurationHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String selected;
  final ValueChanged<String> onChanged;
  final Map<String, String> labels;
  final List<String> durations;

  const _DurationHeaderDelegate({
    required this.selected,
    required this.onChanged,
    required this.labels,
    required this.durations,
  });

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  bool shouldRebuild(covariant _DurationHeaderDelegate old) =>
      old.selected != selected;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Text(
            'I have',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          ...durations.map((d) {
            final isActive = d == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ChoiceChip(
                  label: Text(labels[d] ?? d),
                  selected: isActive,
                  onSelected: (_) => onChanged(d),
                  selectedColor: Colors.black,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : AppColors.textPrimary,
                  ),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MuseumExtraInfo {
  final String website;
  final String hours;
  const _MuseumExtraInfo({required this.website, required this.hours});
}
