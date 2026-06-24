import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/core/services/cloud_storage_service.dart';
import 'package:nexaround_app/features/travel_stories/data/datasources/travel_stories_service.dart';
import 'package:nexaround_app/core/constants/countries.dart';

class CreateJournalSheet extends StatefulWidget {
  final Function(TravelStory) onJournalSubmitted;

  const CreateJournalSheet({Key? key, required this.onJournalSubmitted}) : super(key: key);

  @override
  State<CreateJournalSheet> createState() => _CreateJournalSheetState();
}

class _CreateJournalSheetState extends State<CreateJournalSheet> {
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  final _spendController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  CloudProvider _cloudProvider = CloudProvider.googleDrive;
  bool _isUploading = false;
  
  final List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  String? _selectedCountry;

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (pickedFiles.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(pickedFiles.map((f) => File(f.path)));
        });
      }
    } catch (e) {
      print('Error picking images: $e');
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_locationController.text.isEmpty || _descController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out location and description')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      // 1. Upload to cloud (mocked in our scaffold)
      final storageService = CloudStorageService();
      final folderUrl = await storageService.connectAndUpload(
        _cloudProvider, 
        _selectedImages.map((f) => f.path).toList()
      );

      // 1.5 Upload to backend so they can be shown in the Nexaround app
      final uploadedImageUrls = await TravelStoriesService().uploadImages(
        _selectedImages.map((f) => f.path).toList()
      );

      // 2. Create TravelStory model
      final authState = context.read<AuthBloc>().state;
      String userId = '';
      String userName = 'Journaler';
      
      if (authState is AuthAuthenticated) {
        userId = authState.user.id;
        userName = authState.user.displayName;
        if (userName.trim().isEmpty || userName.trim().toLowerCase() == 'anonymous') {
          userName = authState.user.email.isNotEmpty ? authState.user.email.split('@')[0] : 'Journaler';
        }
      }

      final String currency = (authState is AuthAuthenticated) 
          ? (authState.user.preferences['currency'] ?? 'USD') 
          : 'USD';

      final newJournal = TravelStory(
        id: 'journal_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        userName: userName,
        userAvatar: '',
        locationName: _locationController.text,
        category: 'Journal',
        description: _descController.text,
        imageUrl: (uploadedImageUrls != null && uploadedImageUrls.isNotEmpty) ? uploadedImageUrls.first : '',
        imageUrls: uploadedImageUrls ?? [],
        comments: [],
        createdAt: DateTime.now(),
        isPublic: false,
        isJournal: true,
        journalDate: _selectedDate,
        totalSpend: double.tryParse(_spendController.text) ?? 0.0,
        spendCurrency: currency,
        cloudProvider: _cloudProvider == CloudProvider.dropbox
          ? 'dropbox'
          : 'google_drive',
        cloudFolderUrl: folderUrl,
        country: _selectedCountry,
      );

      widget.onJournalSubmitted(newJournal);
      if (mounted) Navigator.pop(context);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final currentCurrency = (authState is AuthAuthenticated) 
        ? (authState.user.preferences['currency'] ?? 'USD') 
        : 'USD';

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Journal Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Date Picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),
            
            // Location
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),

            // Country Selection
            const Text('Select Country', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCountry,
                  isExpanded: true,
                  hint: const Text('Select Country', style: TextStyle(fontSize: 14)),
                  icon: const Icon(Icons.arrow_drop_down),
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCountry = newValue;
                    });
                  },
                  items: countriesList.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Description
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'What did you do today?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            
            // Photo Attachments
            const Text('Add Photos', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_selectedImages.isEmpty)
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, color: Colors.grey, size: 30),
                      SizedBox(height: 8),
                      Text('Tap to select photos', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _selectedImages.length) {
                      return GestureDetector(
                        onTap: _pickImages,
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: const Icon(Icons.add, color: Colors.grey),
                        ),
                      );
                    }
                    return Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_selectedImages[index], fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedImages.removeAt(index)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            
            // Spend
            TextField(
              controller: _spendController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Total Spend ($currentCurrency)', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            
            const Text('Save Photos To:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Radio<CloudProvider>(
                  value: CloudProvider.dropbox,
                  groupValue: _cloudProvider,
                  onChanged: (v) => setState(() => _cloudProvider = v!),
                ),
                const Icon(Icons.cloud_done, color: Colors.blue),
                const SizedBox(width: 4),
                const Text('Dropbox', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 12),
                Radio<CloudProvider>(
                  value: CloudProvider.googleDrive,
                  groupValue: _cloudProvider,
                  onChanged: (v) => setState(() => _cloudProvider = v!),
                ),
                const Icon(Icons.add_to_drive, color: Colors.blueAccent),
                const SizedBox(width: 4),
                const Text('Google Drive', style: TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 20),
            
            // Submit
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.7),
                ),
                onPressed: _isUploading ? null : _submit,
                child: _isUploading 
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('Save to Journal', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
