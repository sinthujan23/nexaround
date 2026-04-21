import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/ai_companion/presentation/pages/ai_chat_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';

class ArCameraPage extends StatefulWidget {
  const ArCameraPage({super.key});

  @override
  State<ArCameraPage> createState() => _ArCameraPageState();
}

class _ArCameraPageState extends State<ArCameraPage> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _showInfoCard = false;
  int _selectedLandmark = -1;
  String _arMode = 'explore'; // explore, navigate, photo, mapping
  int _nexusPoints = 1250;
  bool _isMapping = false;
  bool _isSavingMapping = false;
  String _selectedCategory = 'HIDDEN';
  final TextEditingController _newPlaceController = TextEditingController();
  final TextEditingController _newPlaceDescriptionController = TextEditingController();

  final List<Map<String, dynamic>> _mappingCategories = [
    {'id': 'HERITAGE', 'icon': Icons.account_balance_rounded, 'label': 'Heritage'},
    {'id': 'DINING', 'icon': Icons.restaurant_rounded, 'label': 'Dining'},
    {'id': 'VIEWPOINT', 'icon': Icons.photo_camera_rounded, 'label': 'Viewpoint'},
    {'id': 'SECRET', 'icon': Icons.vpn_key_rounded, 'label': 'Secret Spot'},
    {'id': 'NATURE', 'icon': Icons.park_rounded, 'label': 'Nature'},
  ];

  final List<_ArLandmark> _landmarks = [
    _ArLandmark('Lotus Temple', 'assets/images/lotus_temple.png', 4.9, '200 m', Offset(0.3, 0.35), 'A beautiful temple with stunning architecture dating back to the 12th century.', 'HERITAGE'),
    _ArLandmark('Colombo Museum', 'assets/images/sigiriya.png', 4.6, '450 m', Offset(0.65, 0.28), 'National museum housing artifacts from Sri Lanka\'s rich history.', 'CULTURE'),
    _ArLandmark('Food Corner', 'assets/images/food_corner.png', 4.3, '120 m', Offset(0.5, 0.55), 'Famous local street food spot known for authentic hoppers and kottu.', 'CUISINE'),
    _ArLandmark('Craft Market', 'assets/images/craft_market.png', 4.1, '300 m', Offset(0.8, 0.48), 'Traditional handicraft market with local artisan goods.', 'ARTISAN'),
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Real camera background
          _buildCameraBackground(),

          // AR landmark labels
          ..._landmarks.asMap().entries.map((e) => _buildLandmarkMarker(e.key, e.value)),

          // Top controls
          _buildTopBar(),

          // AR mode selector
          _buildModeSelector(),

          // AR navigation arrows (when in navigate mode)
          if (_arMode == 'navigate') _buildNavigationOverlay(),

          // Photo enhancement (when in photo mode)
          if (_arMode == 'photo') _buildPhotoOverlay(),

          // Expanded info card
          if (_showInfoCard && _selectedLandmark >= 0) ...[
            _buildInfoCard(_landmarks[_selectedLandmark]),
            // Floating NEVA
            Positioned(
              left: 30,
              bottom: MediaQuery.of(context).size.height * 0.85 - 40,
              child: GestureDetector(
                onTap: () {
                  final landmark = _landmarks[_selectedLandmark];
                  HomePage.homeKey.currentState?.switchToNeva('Tell me more about the ${landmark.name}');
                },
                child: Column(
                  children: [
                    _buildNevaAvatar(80)
                     .animate(onPlay: (c) => c.repeat(reverse: true))
                     .moveY(begin: -5, end: 5, duration: 2.seconds, curve: Curves.easeInOut),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                      child: const Text('ASK NEVA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ),
                  ],
                ),
              ),
            ).animate().fade().scale(begin: const Offset(0.5, 0.5)),
          ],

          // DISCOVERY CROSSHAIR (Only in Mapping Mode)
          if (_isMapping) _buildDiscoveryCrosshair(),

          // MAPPING FORM OVERLAY
          if (_isMapping) _buildMappingOverlay(),
        ],
      ),
    );
  }

  Widget _buildNevaAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: const Color(0xFF64B5F6).withOpacity(0.5), blurRadius: 15, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset(
          'assets/images/neva_avatar.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFF1976D2),
            child: const Center(
              child: Icon(Icons.face_5_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraBackground() {
    if (!_isCameraReady || _controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white24),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize!.height,
          height: _controller!.value.previewSize!.width,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }



  Widget _buildCornerBracket(Alignment alignment) {
    final isTop = alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft = alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;

    return Positioned(
      top: isTop ? 80 : null,
      bottom: isTop ? null : 120,
      left: isLeft ? 20 : null,
      right: isLeft ? null : 20,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? BorderSide(color: AppColors.primary, width: 2) : BorderSide.none,
            bottom: !isTop ? BorderSide(color: AppColors.primary, width: 2) : BorderSide.none,
            left: isLeft ? BorderSide(color: AppColors.primary, width: 2) : BorderSide.none,
            right: !isLeft ? BorderSide(color: AppColors.primary, width: 2) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildLandmarkMarker(int index, _ArLandmark landmark) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Positioned(
      left: screenW * landmark.position.dx - 50,
      top: screenH * landmark.position.dy - 20,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedLandmark = index;
            _showInfoCard = true;
          });
        },
        child: Column(
          children: [
            // Label card
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cinematic Image instead of Icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset( landmark.imagePath, fit: BoxFit.cover ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              landmark.category,
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1),
                            ),
                            Text(
                              landmark.name,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text('${landmark.rating}', style: const TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                Container(width: 2, height: 2, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white38)),
                                const SizedBox(width: 4),
                                Text(landmark.distance, style: const TextStyle(fontSize: 9, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Connector line
            Container(
              width: 1,
              height: 20,
              color: AppColors.primary.withOpacity(0.4),
            ),
            // Pulse dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.6), blurRadius: 8)],
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(1, 1), end: const Offset(1.5, 1.5), duration: 1.seconds),
          ],
        ),
      ).animate().fade(delay: Duration(milliseconds: 300 + index * 200)).scale(begin: const Offset(0.8, 0.8)),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'AR ACTIVE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: 1.5),
                      ),
                      const SizedBox(width: 12),
                      Container(width: 1, height: 12, color: Colors.black12),
                      const SizedBox(width: 12),
                      Icon(Icons.stars_rounded, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '$_nexusPoints XP',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Discovery Button
            GestureDetector(
              onTap: () => setState(() => _isMapping = !_isMapping),
              child: AnimatedContainer(
                duration: 400.ms,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: _isMapping ? AppColors.primaryGradient : null,
                  color: _isMapping ? null : Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _isMapping ? Colors.white30 : Colors.white10),
                  boxShadow: _isMapping ? [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 20)] : null,
                ),
                child: Row(
                  children: [
                    Icon(_isMapping ? Icons.close_rounded : Icons.add_location_alt_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _isMapping ? 'STOP MAPPING' : 'MAP NEW PLACE',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
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



  Widget _buildModeSelector() {
    return Positioned(
      right: -20,
      bottom: 120, // Sit above the navbar but tucked in the corner
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 40, 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeButton(Icons.explore_rounded, 'explore'),
                const SizedBox(height: 12),
                _buildModeButton(Icons.navigation_rounded, 'navigate'),
                const SizedBox(height: 12),
                _buildModeButton(Icons.camera_enhance_rounded, 'photo'),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.5, end: 0);
  }

  Widget _buildModeButton(IconData icon, String mode) {
    final isActive = _arMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _arMode = mode;
        _showInfoCard = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.white : Colors.white10,
          boxShadow: isActive ? [BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 15)] : null,
        ),
        child: Icon(
          icon, 
          color: isActive ? Colors.black : Colors.white, 
          size: 22
        ),
      ),
    );
  }

  Widget _buildNavigationOverlay() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.4,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // Direction arrow
          ShaderMask(
            shaderCallback: (b) => AppColors.primaryGradient.createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
            child: const Icon(Icons.navigation_rounded, size: 80, color: Colors.white),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -10, end: 10, duration: 1.seconds),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text('Head North', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('200m to Lotus Temple', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ).animate().fade(delay: 200.ms),
    );
  }

  Widget _buildPhotoOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Rule of thirds grid
          ...List.generate(2, (i) => Positioned(
            left: MediaQuery.of(context).size.width * (i + 1) / 3,
            top: 80,
            bottom: 120,
            child: Container(width: 0.5, color: AppColors.primary.withOpacity(0.3)),
          )),
          ...List.generate(2, (i) => Positioned(
            top: 80 + (MediaQuery.of(context).size.height - 200) * (i + 1) / 3,
            left: 0,
            right: 0,
            child: Container(height: 0.5, color: AppColors.primary.withOpacity(0.3)),
          )),
          // Best angle indicator
          Positioned(
            top: 130,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black.withOpacity(0.1)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: Colors.black),
                        const SizedBox(width: 6),
                        Text('Best Angle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fade(),
        ],
      ),
    );
  }

  bool _isListening = false;

  Widget _buildInfoCard(_ArLandmark landmark) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85, 
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.85),
              Colors.black.withOpacity(0.98),
            ],
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 40, 30, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              landmark.name.toUpperCase(),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                '✨ AI VERIFIED LANDMARK • ${landmark.distance}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _showInfoCard = false;
                          _isListening = false;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Immersive Description
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        landmark.description + "\n\n" + 
                        "This location is a testament to the city's rich architectural evolution. Our AI models suggest that the lighting here is optimal for photography between 4 PM and 6 PM. The surrounding area is known for its high safety index and local artisan heritage.",
                        style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8), height: 1.8, fontWeight: FontWeight.w400, letterSpacing: 0.2),
                      ),
                    ),
                  ),
                  
                  // LIVE WAVEFORM (Hard-coded interaction)
                  if (_isListening) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(15, (i) => Container(
                        width: 4,
                        height: 10 + Random().nextInt(40).toDouble(),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                       .scaleY(begin: 0.5, end: 1.5, duration: (300 + i * 50).ms, curve: Curves.easeInOut)),
                    ),
                    const SizedBox(height: 12),
                    const Center(child: Text('NEVA IS NARRATING...', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2))),
                  ],

                  const SizedBox(height: 40),
                  // AI GUIDE ACTION
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isListening = !_isListening),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 64,
                            decoration: BoxDecoration(
                              color: _isListening ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: (_isListening ? AppColors.primary : Colors.white).withOpacity(0.3), blurRadius: 30)],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isListening ? Icons.pause_rounded : Icons.graphic_eq_rounded, 
                                  color: _isListening ? Colors.white : Colors.black, 
                                  size: 26
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isListening ? 'STOP NARRATION' : 'NEVA NARRATION',
                                  style: TextStyle(
                                    color: _isListening ? Colors.white : Colors.black, 
                                    fontWeight: FontWeight.w900, 
                                    fontSize: 14, 
                                    letterSpacing: 1
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 800.ms, curve: Curves.easeOutQuart);
  }

  Widget _buildDiscoveryCrosshair() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 2), // Darker outer ring
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 2.seconds, curve: Curves.easeInOut),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 3), // Strong dark outline
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 2),
              shape: BoxShape.circle,
            ),
          ),
          Container(width: 4, height: 22, color: Colors.black), // Black shadow for vertical line
          Container(width: 2, height: 20, color: AppColors.primary),
          Container(width: 22, height: 4, color: Colors.black), // Black shadow for horizontal line
          Container(width: 20, height: 2, color: AppColors.primary),
        ],
      ),
    ).animate().fade().scale(begin: const Offset(2, 2));
  }

  Widget _buildMappingOverlay() {
    return Positioned(
      bottom: 120,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _buildNevaAvatar(50),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    '"Point at the center of the place and lock the coordinates."',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _newPlaceController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Place Name (e.g. Secret Rooftop)',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.white70, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            // Category Picker
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _mappingCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final cat = _mappingCategories[index];
                  final isSelected = _selectedCategory == cat['id'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat['id']),
                    child: AnimatedContainer(
                      duration: 300.ms,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? Colors.white30 : Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          Icon(cat['icon'], color: Colors.white, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            cat['label'],
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPlaceDescriptionController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'What makes this place special...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                if (_newPlaceController.text.isEmpty) return;
                setState(() => _isSavingMapping = true);
                
                // Simulate spatial locking
                await Future.delayed(const Duration(milliseconds: 1500));
                
                if (mounted) {
                  setState(() {
                    _nexusPoints += 50;
                    _isMapping = false;
                    _isSavingMapping = false;
                    _landmarks.add(_ArLandmark(
                      _newPlaceController.text, 
                      'assets/images/lotus_temple.png', 
                      5.0, 
                      '0 m', 
                      const Offset(0.5, 0.5), 
                      _newPlaceDescriptionController.text.isEmpty ? 'Discovered by you.' : _newPlaceDescriptionController.text, 
                      _selectedCategory
                    ));
                    _newPlaceController.clear();
                    _newPlaceDescriptionController.clear();
                    _selectedCategory = 'HIDDEN';
                  });
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      content: GlassCard(
                        padding: const EdgeInsets.all(16),
                        glowColor: Colors.amber,
                        child: Row(
                          children: [
                            const Icon(Icons.stars_rounded, color: Colors.amber),
                            const SizedBox(width: 12),
                            const Text('DISCOVERY SAVED! +50 NEXUS POINTS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                          ],
                        ),
                      ),
                    )
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 20)],
                ),
                child: Center(
                  child: _isSavingMapping 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('LOCK SPATIAL ANCHOR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart);
  }
}

class _ArLandmark {
  final String name;
  final String imagePath;
  final double rating;
  final String distance;
  final Offset position;
  final String description;
  final String category;

  const _ArLandmark(this.name, this.imagePath, this.rating, this.distance, this.position, this.description, this.category);
}
