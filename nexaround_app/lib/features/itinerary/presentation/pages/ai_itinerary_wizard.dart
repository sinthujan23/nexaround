import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

class AiItineraryWizard extends StatefulWidget {
  final String location;
  const AiItineraryWizard({super.key, required this.location});

  @override
  State<AiItineraryWizard> createState() => _AiItineraryWizardState();
}

class _AiItineraryWizardState extends State<AiItineraryWizard> {
  bool _isLoading = true;
  dynamic _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generatePlan();
  }

  Future<void> _generatePlan() async {
    try {
      final response = await ApiClient.instance.post(
        '${ApiConstants.baseUrl}/itineraries/generate',
        queryParameters: {'location': widget.location, 'days': 2},
      );
      setState(() {
        _plan = response.data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('AI Trip Designer'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
        ? _buildLoading()
        : _error != null 
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _buildPlanView(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.secondary),
          const SizedBox(height: 24),
          const Text(
            'Designing your perfect trip...',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Text(
            'Analyzing attractions in ${widget.location}',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanView() {
    final List days = _plan is Map ? (_plan['plan'] ?? []) : (_plan as List);
    
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        return _buildDayCard(day);
      },
    );
  }

  Widget _buildDayCard(dynamic day) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAY ${day['day']}: ${day['theme'].toString().toUpperCase()}',
            style: const TextStyle(
              color: AppColors.secondary, 
              fontWeight: FontWeight.w700, 
              fontSize: 14,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ...(day['activities'] as List).map((act) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
                  ),
                  child: Text(
                    act['time'], 
                    style: const TextStyle(color: AppColors.secondary, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        act['attraction_name'],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        act['tip'],
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    ),
        ),
      ),
    );
  }
}
