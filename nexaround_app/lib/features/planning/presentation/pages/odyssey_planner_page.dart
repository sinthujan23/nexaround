import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';

class OdysseyPlannerPage extends StatefulWidget {
  const OdysseyPlannerPage({super.key});

  @override
  State<OdysseyPlannerPage> createState() => _OdysseyPlannerPageState();
}

class _OdysseyPlannerPageState extends State<OdysseyPlannerPage> {
  int _currentStep = 0;
  double _budget = 50000;
  String _selectedMood = 'Adventurous';

  final List<Map<String, dynamic>> _moods = [
    {'name': 'Affordable', 'icon': Icons.savings_rounded, 'desc': 'Focus on local gems'},
    {'name': 'Luxury', 'icon': Icons.diamond_rounded, 'desc': 'Premium experiences'},
    {'name': 'Adventurous', 'icon': Icons.terrain_rounded, 'desc': 'Unexplored trails'},
    {'name': 'Cultural', 'icon': Icons.museum_rounded, 'desc': 'Deep heritage'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'NEXUS ODYSSEY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        children: List.generate(3, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive ? Colors.black : Colors.black12,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildMoodStep();
      case 1: return _buildBudgetStep();
      case 2: return _buildResultStep();
      default: return const SizedBox();
    }
  }

  Widget _buildMoodStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How do you want to\nexperience the world?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade().slideY(begin: 0.1, end: 0),
          const SizedBox(height: 32),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _moods.length,
            itemBuilder: (context, index) {
              final mood = _moods[index];
              final isSelected = _selectedMood == mood['name'];
              return GestureDetector(
                onTap: () => setState(() => _selectedMood = mood['name']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: isSelected ? Colors.black : Colors.black12),
                    boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))] : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(mood['icon'], color: isSelected ? Colors.white : Colors.black, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        mood['name'],
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : Colors.black),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mood['desc'],
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: isSelected ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ).animate().fade(delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildBudgetStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What is your\naffordable limit?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade(),
          const SizedBox(height: 12),
          const Text(
             'AI will optimize the odyssey based on this cap.',
             style: TextStyle(color: Colors.black54),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Text(
                  'LKR ${_budget.toInt()}',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -1),
                ),
                const Text('ESTIMATED BUDGET CONTENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2)),
              ],
            ),
          ).animate().scale(),
          const Spacer(),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.black,
              inactiveTrackColor: Colors.black12,
              thumbColor: Colors.black,
              overlayColor: Colors.black.withOpacity(0.1),
              trackHeight: 8,
            ),
            child: Slider(
              value: _budget,
              min: 10000,
              max: 200000,
              onChanged: (val) => setState(() => _budget = val),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildResultStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.ratingGold, borderRadius: BorderRadius.circular(8)),
            child: const Text('AI GENERATED ODYSSEY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 16),
          const Text(
            'The Golden Triangle\nCircuit',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: 24),
          _buildResultCard('Duration', '4 Days / 3 Nights', Icons.wb_sunny_rounded),
          _buildResultCard('Visa Status', 'ETA Available (Online)', Icons.description_rounded),
          _buildResultCard('Budget Split', '40% Stay, 30% Food, 30% Exp', Icons.pie_chart_rounded),
          _buildResultCard('Local Services', 'PickMe/Uber + Local Tuk-tuks', Icons.directions_car_rounded),
          const SizedBox(height: 24),
          const Text(
            'LOGISTICS BLUEPRINT',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black12),
            ),
            child: const Text(
              '1. Apply for ETA 48hrs before arrival.\n2. Use PickMe for airport transfer (approx LKR 4000).\n3. Allocate 15k for Sigiriya entry fees.\n4. Local SIM card available at exit gate 4.',
              style: TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
            ),
          ),
        ],
      ),
    ).animate().fade();
  }

  Widget _buildResultCard(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w700)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 60,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: ElevatedButton(
                onPressed: () {
                  if (_currentStep < 2) {
                    setState(() => _currentStep++);
                  } else {
                    Navigator.pop(context); // Save logic would go here
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(
                  _currentStep == 2 ? 'SAVE TO MY ODYSSEYS' : 'CONTINUE',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
