import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/presentation/bloc/review_bloc.dart';
import 'package:intl/intl.dart';

class AttractionDetailPage extends StatefulWidget {
  final AttractionEntity attraction;

  const AttractionDetailPage({super.key, required this.attraction});

  @override
  State<AttractionDetailPage> createState() => _AttractionDetailPageState();
}

class _AttractionDetailPageState extends State<AttractionDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<ReviewBloc>().add(FetchReviews(widget.attraction.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Description'),
                  const SizedBox(height: 8),
                  Text(
                    widget.attraction.description ?? 'No description available for this attraction.',
                    style: const TextStyle(color: Colors.white70, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle('History'),
                  const SizedBox(height: 8),
                  Text(
                    widget.attraction.history ?? 'Detailed history coming soon.',
                    style: const TextStyle(color: Colors.white70, height: 1.6),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Reviews'),
                      TextButton(
                        onPressed: () => _showAddReviewDialog(context),
                        child: const Text('Add Review', style: TextStyle(color: AppColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildReviewsList(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: _buildBottomActions(),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppColors.darkBackground,
      flexibleSpace: FlexibleSpaceBar(
        background: widget.attraction.photoUrls.isNotEmpty
            ? Image.network(widget.attraction.photoUrls[0], fit: BoxFit.cover)
            : Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                child: const Icon(Icons.place_rounded, size: 80, color: Colors.white),
              ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.favorite_border_rounded, color: Colors.white),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.attraction.name,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppColors.primary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    widget.attraction.rating.toStringAsFixed(1),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.location_on_rounded, color: Colors.white38, size: 16),
            const SizedBox(width: 4),
            Text(
              widget.attraction.address ?? 'Colombo, Sri Lanka',
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildReviewsList() {
    return BlocBuilder<ReviewBloc, ReviewState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.reviews.isEmpty) {
          return const Center(
            child: Text('No reviews yet. Be the first!', style: TextStyle(color: Colors.white24)),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: state.reviews.length,
          itemBuilder: (context, index) {
            final review = state.reviews[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        review.userDisplayName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: i < review.rating ? AppColors.primary : Colors.white10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM dd, yyyy').format(review.createdAt),
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                  if (review.comment != null) ...[
                    const SizedBox(height: 8),
                    Text(review.comment!, style: const TextStyle(color: Colors.white70)),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.darkSurface,
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Add to Itinerary', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              icon: const Icon(Icons.directions_rounded, color: Colors.white),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  void _showAddReviewDialog(BuildContext context) {
    int rating = 5;
    final controller = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How was your visit?', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => IconButton(
                  icon: Icon(
                    Icons.star_rounded,
                    size: 40,
                    color: i < rating ? AppColors.primary : Colors.white10,
                  ),
                  onPressed: () => setModalState(() => rating = i + 1),
                )),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Share your experience...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  context.read<ReviewBloc>().add(PostReview(
                    attractionId: widget.attraction.id,
                    rating: rating,
                    comment: controller.text,
                  ));
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Post Review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
