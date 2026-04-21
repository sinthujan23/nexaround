import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DiscoverySettingsPage extends StatefulWidget {
  const DiscoverySettingsPage({super.key});

  @override
  State<DiscoverySettingsPage> createState() => _DiscoverySettingsPageState();
}

class _DiscoverySettingsPageState extends State<DiscoverySettingsPage> {
  final List<String> _interests = ['Culture', 'Food', 'Nature', 'Nightlife', 'Shopping', 'History', 'Adventure'];
  final List<String> _selectedInterests = [];
  String _travelStyle = 'balanced';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) {
      final user = state.user;
      final prefs = user.preferences;
      if (prefs['interests'] != null) {
        _selectedInterests.addAll(List<String>.from(prefs['interests']));
      }
      _travelStyle = prefs['travel_style'] ?? 'balanced';
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await ApiClient.instance.put(
        '${ApiConstants.baseUrl}/auth/me/preferences',
        data: {
          'interests': _selectedInterests,
          'travel_style': _travelStyle,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI profile optimized successfully.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI PERSONALIZATION',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Your Passions', 'Fine-tune the curation engine to your soul')
                .animate().fade().slideY(begin: 0.2, end: 0),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _interests.asMap().entries.map((entry) {
                final interest = entry.value;
                final index = entry.key;
                final isSelected = _selectedInterests.contains(interest);
                return _buildGalleryChip(interest, isSelected)
                    .animate().fade(delay: (index * 50).ms).scale(delay: (index * 50).ms);
              }).toList(),
            ),
            const SizedBox(height: 48),
            _buildSectionHeader('Exploration Rhythm', 'Define the pace of your discovery journeys')
                .animate().fade(delay: 400.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 24),
            _buildStyleOption('Relaxed Essence', 'Slow pace, profound connection', Icons.spa_rounded, 'relaxed', 0),
            _buildStyleOption('Balanced Pulse', 'The perfect harmony of rest and movement', Icons.balance_rounded, 'balanced', 1),
            _buildStyleOption('High-Energy Current', 'Dynamic pace, covering the world\'s width', Icons.bolt_rounded, 'active', 2),
            const SizedBox(height: 64),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 15,
                  shadowColor: AppColors.primary.withOpacity(0.4),
                ),
                child: _isSaving 
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'OPTIMIZE MY JOURNEY',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 2),
                    ),
              ),
            ).animate().fade(delay: 800.ms).slideY(begin: 0.3, end: 0),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedInterests.remove(label);
          } else {
            _selectedInterests.add(label);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title, 
          style: const TextStyle(
            color: AppColors.textPrimary, 
            fontSize: 24, 
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle, 
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildStyleOption(String title, String subtitle, IconData icon, String value, int index) {
    final isSelected = _travelStyle == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => setState(() => _travelStyle = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected 
                  ? AppColors.primary.withOpacity(0.08) 
                  : Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon, 
                color: isSelected ? Colors.white : AppColors.textTertiary, 
                size: 24,
              ),
            ),
            title: Text(
              title, 
              style: const TextStyle(
                color: AppColors.textPrimary, 
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle, 
                style: TextStyle(
                  color: AppColors.textSecondary, 
                  fontSize: 12,
                ),
              ),
            ),
            trailing: isSelected 
              ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 24) 
              : null,
          ),
        ),
      ).animate().fade(delay: (500 + index * 100).ms).slideX(begin: 0.1, end: 0),
    );
  }
}
