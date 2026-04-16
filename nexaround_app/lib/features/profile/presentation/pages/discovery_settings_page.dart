import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';

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
    // Load current preferences from AuthBloc
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
          const SnackBar(content: Text('Preferences updated! AI is now tailored to you.')),
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
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('AI Personalization'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Your Interests', 'Tell Gemini what you love discover'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _interests.map((interest) {
                final isSelected = _selectedInterests.contains(interest);
                return FilterChip(
                  label: Text(interest),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withOpacity(0.2),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primary : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.white.withOpacity(0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedInterests.add(interest);
                      } else {
                        _selectedInterests.remove(interest);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 40),
            _buildSectionHeader('Travel Style', 'How do you like to explore?'),
            const SizedBox(height: 16),
            _buildStyleOption('Relaxed', 'Slow pace, deep exploration', Icons.spa_rounded, 'relaxed'),
            _buildStyleOption('Balanced', 'A mix of everything', Icons.balance_rounded, 'balanced'),
            _buildStyleOption('Active', 'High energy, covering more ground', Icons.directions_run_rounded, 'active'),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isSaving 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Update AI Persona', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5))),
      ],
    );
  }

  Widget _buildStyleOption(String title, String subtitle, IconData icon, String value) {
    final isSelected = _travelStyle == value;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
      ),
      child: ListTile(
        onTap: () => setState(() => _travelStyle = value),
        leading: Icon(icon, color: isSelected ? AppColors.primary : Colors.white38),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: isSelected ? Colors.white54 : Colors.white24, fontSize: 12)),
        trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
      ),
    );
  }
}
