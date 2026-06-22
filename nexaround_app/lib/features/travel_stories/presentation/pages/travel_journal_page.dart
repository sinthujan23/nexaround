import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/core/services/cloud_storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nexaround_app/features/travel_stories/presentation/widgets/create_journal_sheet.dart';
import 'package:nexaround_app/features/travel_stories/data/datasources/travel_stories_service.dart';

class TravelJournalPage extends StatefulWidget {
  const TravelJournalPage({Key? key}) : super(key: key);

  @override
  State<TravelJournalPage> createState() => _TravelJournalPageState();
}

class _TravelJournalPageState extends State<TravelJournalPage> {
  final List<TravelStory> _journalEntries = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchJournalEntries();
  }

  Future<void> _fetchJournalEntries() async {
    setState(() => _isLoading = true);
    final stories = await TravelStoriesService().getStories();
    
    // Filter only journal entries
    final journals = stories.where((s) => s.isJournal == true).toList();
    
    if (mounted) {
      setState(() {
        _journalEntries.clear();
        _journalEntries.addAll(journals);
        _isLoading = false;
      });
    }
  }

  void _openCloudFolder(String? url) async {
    if (url != null) {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $url')),
          );
        }
      }
    }
  }

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateJournalSheet(
        onJournalSubmitted: (newEntry) async {
          // Save to Hive Local Database
          await TravelStoriesService().addStory(newEntry);
          
          setState(() {
            _journalEntries.insert(0, newEntry);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Travel Journal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openCreateSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _journalEntries.isEmpty
              ? _buildEmptyState()
              : _buildTimeline(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.book_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Your Journal is Empty',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep daily notes and track your spending!',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openCreateSheet,
            icon: const Icon(Icons.add),
            label: const Text('Add Entry'),
          )
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _journalEntries.length,
      itemBuilder: (context, index) {
        final entry = _journalEntries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.journalDate != null 
                        ? '${entry.journalDate!.day}/${entry.journalDate!.month}/${entry.journalDate!.year}'
                        : 'No Date',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${entry.totalSpend} ${entry.spendCurrency}',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(entry.locationName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(entry.description),
                const SizedBox(height: 16),
                if (entry.cloudFolderUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _openCloudFolder(entry.cloudFolderUrl),
                    icon: Icon(
                      _getCloudProviderIcon(entry.cloudProvider),
                      color: Colors.blue,
                    ),
                    label: Text('View Photos in ${_formatCloudProviderName(entry.cloudProvider)}'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getCloudProviderIcon(String? provider) {
    switch (provider) {
      case 'dropbox':
        return Icons.cloud_done;
      case 'one_drive':
        return Icons.cloud;
      default:
        return Icons.folder_shared;
    }
  }

  String _formatCloudProviderName(String? provider) {
    switch (provider) {
      case 'dropbox':
        return 'Dropbox';
      case 'one_drive':
        return 'OneDrive';
      default:
        return 'Cloud';
    }
  }
}
