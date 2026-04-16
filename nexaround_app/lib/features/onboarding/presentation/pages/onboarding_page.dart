import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';

class InteractiveOnboardingPage extends StatefulWidget {
  const InteractiveOnboardingPage({super.key});

  @override
  State<InteractiveOnboardingPage> createState() => _InteractiveOnboardingPageState();
}

class _InteractiveOnboardingPageState extends State<InteractiveOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<String> _selectedInterests = [];
  String _travelStyle = 'balanced';

  final List<String> _interests = ['Nature', 'Food', 'Culture', 'Adventure', 'Shopping', 'History', 'Nightlife'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: List.generate(3, (index) => Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index <= _currentPage ? AppColors.primary : Colors.white10,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )),
              ),
            ),
            
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomeStep(),
                  _buildInterestsStep(),
                  _buildStyleStep(),
                ],
              ),
            ),
            
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 80, color: AppColors.primary),
          ),
          const SizedBox(height: 40),
          const Text(
            'Meet your AI Guide',
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Let\'s personalize your NexAround experience for truly unique discoveries.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInterestsStep() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          const Text('What do you love?', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Select at least 3 to help Gemini understand you.', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 40),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: _interests.map((interest) {
              final isSelected = _selectedInterests.contains(interest);
              return FilterChip(
                label: Text(interest),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) _selectedInterests.add(interest);
                    else _selectedInterests.remove(interest);
                  });
                },
                backgroundColor: Colors.white10,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleStep() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          const Text('Your Travel Style', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          _buildStyleCard('Relaxed', 'Take it slow and soak it in.', Icons.spa_rounded, 'relaxed'),
          const SizedBox(height: 16),
          _buildStyleCard('Balanced', 'A healthy mix of everything.', Icons.explore_rounded, 'balanced'),
          const SizedBox(height: 16),
          _buildStyleCard('Active', 'See as much as possible.', Icons.bolt_rounded, 'active'),
        ],
      ),
    );
  }

  Widget _buildStyleCard(String title, String subtitle, IconData icon, String value) {
    final isSelected = _travelStyle == value;
    return GestureDetector(
      onTap: () => setState(() => _travelStyle = value),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : Colors.white38),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: ElevatedButton(
        onPressed: () {
          if (_currentPage < 2) {
            _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          } else {
            _finishOnboarding();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(_currentPage == 2 ? 'Start My Adventure' : 'Continue', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    try {
      await ApiClient.instance.put(
        '${ApiConstants.baseUrl}/auth/me/preferences',
        data: {
          'interests': _selectedInterests,
          'travel_style': _travelStyle,
        },
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } catch (e) {
      // Success anyway logic for demo, or handle error
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      }
    }
  }
}
