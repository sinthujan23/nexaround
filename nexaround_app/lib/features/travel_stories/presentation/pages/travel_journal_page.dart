import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/create_journal_sheet.dart';
import 'package:nexaround_app/features/travel_stories/data/datasources/travel_stories_service.dart';
import 'package:nexaround_app/core/widgets/full_screen_image_viewer.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/core/services/cloud_storage_service.dart';

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
    // 1. Instantly load from cache
    final cached = TravelStoriesService().getCachedJournals();
    if (mounted) {
      setState(() {
        _journalEntries.clear();
        _journalEntries.addAll(cached);
        _isLoading = cached.isEmpty; // Only show loader if cache is empty
      });
    }

    // 2. Fetch fresh data from backend
    final journals = await TravelStoriesService().getJournals();
    
    if (mounted) {
      setState(() {
        _journalEntries.clear();
        _journalEntries.addAll(journals);
        _isLoading = false;
      });
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Travel Journal'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openCreateSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandGreen))
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _journalEntries.length,
      itemBuilder: (context, index) {
        final entry = _journalEntries[index];
        final dateStr = entry.journalDate != null 
          ? '${entry.journalDate!.day}/${entry.journalDate!.month}/${entry.journalDate!.year}'
          : 'No Date';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.015),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.brandGreen.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.book_rounded,
                color: AppColors.brandGreen,
                size: 20,
              ),
            ),
            title: Text(
              entry.locationName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                dateStr,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.black38,
            ),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => JournalDetailPage(entry: entry),
                ),
              );
              if (result == true) {
                _fetchJournalEntries();
              }
            },
          ),
        );
      },
    );
  }
}

class JournalDetailPage extends StatefulWidget {
  final TravelStory entry;
  const JournalDetailPage({Key? key, required this.entry}) : super(key: key);

  @override
  State<JournalDetailPage> createState() => _JournalDetailPageState();
}

class _JournalDetailPageState extends State<JournalDetailPage> {
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

  Widget _buildImage(String url, int index, List<String> allUrls) {
    return GestureDetector(
      onTap: () {
        final authState = context.read<AuthBloc>().state;
        final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
        final isAuthor = currentUserId == widget.entry.userId;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenImageViewer(
              imageUrls: allUrls,
              initialIndex: index,
              showDeleteOption: isAuthor,
              onDelete: () async {
                await _deleteJournal();
              },
            ),
          ),
        );
      },
      child: _buildImageContent(url),
    );
  }

  Widget _buildImageContent(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade100,
          child: const Icon(Icons.broken_image_outlined, color: Colors.black26),
        ),
      );
    } else if (url.startsWith('/static/')) {
      final fullUrl = '${ApiConstants.baseUrl}$url';
      return CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade100,
          child: const Icon(Icons.broken_image_outlined, color: Colors.black26),
        ),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
        );
      } else {
        final fullUrl = url.startsWith('/') ? '${ApiConstants.baseUrl}$url' : url;
        return CachedNetworkImage(
          imageUrl: fullUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey.shade100,
            child: const Icon(Icons.broken_image_outlined, color: Colors.black26),
          ),
        );
      }
    }
  }

  Future<void> _deleteJournal() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Journal', style: TextStyle(color: Colors.black)),
        content: const Text(
          'Are you sure you want to delete this entire journal post? If it was saved to the cloud, it will also be deleted from there.',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleting Journal...')),
        );
      }
      try {
        if (widget.entry.cloudFolderUrl != null && widget.entry.cloudProvider != null) {
          final provider = widget.entry.cloudProvider == 'google_drive' 
              ? CloudProvider.googleDrive 
              : CloudProvider.dropbox;
          try {
            await CloudStorageService().deleteFromCloud(provider, widget.entry.cloudFolderUrl!);
          } catch (e) {
            print("Failed to delete from cloud: $e");
          }
        }
        await TravelStoriesService().deleteStory(widget.entry.id);
        if (mounted) {
          Navigator.pop(context, true); // Pop back to journal list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final dateStr = entry.journalDate != null
        ? '${entry.journalDate!.day}/${entry.journalDate!.month}/${entry.journalDate!.year}'
        : 'No Date';

    final allUrls = entry.imageUrls.isNotEmpty
        ? entry.imageUrls
        : (entry.imageUrl.isNotEmpty ? [entry.imageUrl] : <String>[]);

    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final isAuthor = currentUserId == entry.userId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Journal Details'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (isAuthor)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deleteJournal,
            ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black.withOpacity(0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.totalSpend} ${entry.spendCurrency}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded, size: 16, color: AppColors.brandGreen),
                      const SizedBox(width: 6),
                      Text(
                        entry.country != null && entry.country!.trim().isNotEmpty
                            ? '${entry.locationName}, ${entry.country}'
                            : entry.locationName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Description Section
            const Text(
              'DESCRIPTION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              entry.description.isEmpty ? 'No notes added for this entry.' : entry.description,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 32),

            // Images Gallery Section
            if (allUrls.isNotEmpty) ...[
              const Text(
                'PHOTOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: allUrls.length,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 180,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withOpacity(0.06)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildImage(allUrls[index], index, allUrls),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],

            // Cloud Link Section
            if (entry.cloudFolderUrl != null && entry.cloudFolderUrl!.isNotEmpty) ...[
              const Text(
                'CLOUD BACKUP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _openCloudFolder(entry.cloudFolderUrl),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getCloudProviderIcon(entry.cloudProvider),
                        color: Colors.blue.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'View Photos in ${_formatCloudProviderName(entry.cloudProvider)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Access the original folder containing all images',
                              style: TextStyle(
                                color: Colors.blue.shade700.withOpacity(0.8),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: Colors.blue.shade700, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getCloudProviderIcon(String? provider) {
    switch (provider) {
      case 'dropbox':
        return Icons.cloud_done;
      default:
        return Icons.cloud;
    }
  }

  String _formatCloudProviderName(String? provider) {
    switch (provider) {
      case 'dropbox':
        return 'Dropbox';
      default:
        return 'Google Drive';
    }
  }
}
