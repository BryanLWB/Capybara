import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/server_node.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../utils/node_utils.dart';
import 'capybara_loader.dart';

class NodePickerSheet extends StatefulWidget {
  final ValueChanged<ServerNode> onNodeSelected;

  const NodePickerSheet({super.key, required this.onNodeSelected});

  @override
  State<NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<NodePickerSheet>
    with SingleTickerProviderStateMixin {
  final _subscriptionService = SubscriptionService();
  List<ServerNode> _nodes = [];
  bool _isLoading = true;
  late AnimationController _breathingController;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _loadNodes();
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  Future<void> _loadNodes({bool force = false}) async {
    setState(() => _isLoading = true);
    try {
      final nodes = await _subscriptionService.fetchNodes(forceRefresh: force);
      if (mounted) {
        setState(() {
          _nodes = nodes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Silently fail or show simple error in UI
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      snap: true,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Stack(
            children: [
              // Glass Effect Background
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: AppColors.surface.withOpacity(0.85)),
              ),

              // Content
              Column(
                children: [
                  _buildHeader(context),
                  if (_isLoading)
                    const Expanded(child: Center(child: CapybaraLoader(size: 30)))
                  else if (_nodes.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context)?.noNodes ??
                              'No Nodes Available',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16).copyWith(bottom: 32),
                        itemCount: _nodes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _buildNodeItem(context, _nodes[index]),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.05), Colors.transparent],
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Title Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)?.selectNode ?? 'Select Node',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _loadNodes(force: true),
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                tooltip: AppLocalizations.of(context)?.refresh,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNodeItem(BuildContext context, ServerNode node) {
    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        final t = _breathingController.value;
        // Breathing opacity for border: oscillates between 0.1 and 0.4
        final borderOpacity = 0.1 + 0.3 * math.sin(t * math.pi);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.03),
            border: Border.all(
              color: AppColors.accent.withOpacity(
                borderOpacity.clamp(0.0, 1.0),
              ),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.pop(context);
                widget.onNodeSelected(node);
              },
              highlightColor: AppColors.accent.withOpacity(0.1),
              splashColor: AppColors.accent.withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // Location Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.public,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Node Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  node.protocol.toUpperCase(),
                                  style: TextStyle(
                                    color: AppColors.textSecondary.withOpacity(
                                      0.8,
                                    ),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (node.latency != null) ...[
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: _getLatencyColor(node.latency!),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${node.latency}ms',
                                  style: TextStyle(
                                    color: _getLatencyColor(node.latency!),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Arrow
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary.withOpacity(0.5),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getLatencyColor(int latency) {
    if (latency < 100) return const Color(0xFF6CFFB8); // Bright Green
    if (latency < 300) return const Color(0xFFFFE18D); // Yellow
    return const Color(0xFFFF8D8D); // Red
  }
}
