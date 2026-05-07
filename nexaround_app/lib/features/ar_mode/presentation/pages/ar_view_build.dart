  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocListener<ArBloc, ArState>(
        listenWhen: (prev, curr) => prev.isMappingMode != curr.isMappingMode,
        listener: (context, state) => _onMappingToggled(state.isMappingMode),
        child: BlocBuilder<ArBloc, ArState>(
          builder: (context, state) {
            return Stack(
              children: [
                // Layer 1: Camera Feed
                _buildCameraFeed(),

                // Layer 2: Subtle scan overlay
                _buildScanOverlay(),

                // Layer 3: AR POI markers in 3D space
                if (state.attractions.isNotEmpty) ..._buildArPOI(state),

                // Layer 4: Top-Left — Place Name Banner
                if (state.detectedAttraction != null) _buildPlaceNameBanner(state),

                // Layer 5: Left — Info Pills
                if (state.detectedAttraction != null) _buildInfoPills(state),

                // Layer 6: Right — Category Icons
                _buildCategoryIcons(state),

                // Layer 7: Top-Right — Status Bar
                _buildStatusBar(state),

                // Layer 8: Bottom — Distance + Address
                if (state.detectedAttraction != null) _buildDistanceBanner(state),

                // Layer 9: Bottom Dock
                _buildBottomDock(state),

                // Layer 10: AI Vision Result Overlay
                if (state.identifiedObject != null) _buildVisionResultOverlay(state),

                // Layer 11: Full Detail Sheet
                if (state.selectedAttraction != null) _buildDetailSheet(state),

                // Layer 12: Discovery Crosshair (Only in Mapping Mode)
                if (state.isMappingMode) _buildDiscoveryCrosshair(),

                // Layer 13: Mapping Form Overlay
                if (state.isMappingMode) _buildMappingOverlay(state),

                // Loading
                if (state.status == ArStatus.loading || state.isScanning)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
              ],
            );
          },
        ),
      ),
    );
  }
