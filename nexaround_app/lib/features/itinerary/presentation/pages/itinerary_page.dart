import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/itinerary/presentation/bloc/itinerary_bloc.dart';
import 'package:intl/intl.dart';
import 'package:nexaround_app/features/itinerary/presentation/pages/ai_itinerary_wizard.dart';
import 'package:nexaround_app/features/profile/presentation/pages/discovery_settings_page.dart';

class ItineraryPage extends StatelessWidget {
  const ItineraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: BlocBuilder<ItineraryBloc, ItineraryState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.itineraries.isEmpty) {
            return _buildEmptyState(context);
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.darkBackground,
                expandedHeight: 120,
                floating: true,
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text('Your Trips', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  titlePadding: EdgeInsets.only(left: 20, bottom: 16),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: Colors.white54),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DiscoverySettingsPage()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AiItineraryWizard(location: 'Colombo')),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                    onPressed: () => _showCreateDialog(context),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final trip = state.itineraries[index];
                      return _TripCard(itinerary: trip);
                    },
                    childCount: state.itineraries.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 80, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 24),
          const Text(
            'No trips planned yet',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Start planning your next adventure!',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _showCreateDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Create New Trip', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('New Trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Trip Name (e.g., Kandy Weekend)',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<ItineraryBloc>().add(CreateItinerary(controller.text));
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final dynamic itinerary;
  const _TripCard({required this.itinerary});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        itinerary.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        itinerary.status.toUpperCase(),
                        style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildInfoChip(Icons.calendar_today_rounded, 
                      itinerary.tripDate != null 
                        ? DateFormat('MMM dd').format(itinerary.tripDate!)
                        : 'Anytime'
                    ),
                    const SizedBox(width: 16),
                    _buildInfoChip(Icons.location_on_rounded, '${itinerary.items.length} spots'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}
