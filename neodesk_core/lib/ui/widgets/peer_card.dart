import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';
import 'status_dot.dart';

/// Maps a peer platform string to an icon + accent tint for its avatar block.
({IconData icon, Color tint}) _platformVisual(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('android')) {
    return (icon: Icons.android, tint: const Color(0xFF3DDC84));
  }
  if (p.contains('mac') || p.contains('ios')) {
    return (icon: Icons.laptop_mac, tint: const Color(0xFFAAB2BD));
  }
  if (p.contains('linux')) {
    return (icon: Icons.terminal, tint: const Color(0xFFF5A623));
  }
  return (
    icon: Icons.desktop_windows,
    tint: const Color(0xFF4C9AFF)
  ); // windows
}

/// A row item for the recent / lan device lists. See DESIGN.md §4.1.
class PeerListTile extends StatefulWidget {
  const PeerListTile({
    super.key,
    required this.peer,
    required this.onTap,
    this.onMenu,
  });

  final PeerEntry peer;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  @override
  State<PeerListTile> createState() => _PeerListTileState();
}

class _PeerListTileState extends State<PeerListTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final v = _platformVisual(widget.peer.platform);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onMenu,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: Dimens.listItemHeight,
          margin: const EdgeInsets.symmetric(
              horizontal: Dimens.pageInset, vertical: Dimens.s4),
          padding: const EdgeInsets.symmetric(horizontal: Dimens.s12),
          decoration: BoxDecoration(
            color: _down ? AppColors.bgElevated2 : AppColors.bgElevated1,
            borderRadius: BorderRadius.circular(Dimens.rCard),
          ),
          child: Row(
            children: [
              Container(
                width: Dimens.avatar,
                height: Dimens.avatar,
                decoration: BoxDecoration(
                  color: v.tint.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(Dimens.rChip),
                ),
                child: Icon(v.icon, color: v.tint, size: 22),
              ),
              const SizedBox(width: Dimens.s12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.peer.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.peer.id}  ·  ${widget.peer.platform}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              StatusDot(online: widget.peer.online),
              if (widget.onMenu != null)
                IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: AppColors.textSecondary),
                  onPressed: widget.onMenu,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square-ish card for the horizontal "favourites" shelf. See §4.1.
class PeerShelfCard extends StatelessWidget {
  const PeerShelfCard({super.key, required this.peer, required this.onTap});

  final PeerEntry peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = _platformVisual(peer.platform);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 132,
        margin: const EdgeInsets.only(right: Dimens.s12),
        padding: const EdgeInsets.all(Dimens.s12),
        decoration: BoxDecoration(
          color: AppColors.bgElevated1,
          borderRadius: BorderRadius.circular(Dimens.rCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: v.tint.withOpacity(0.18),
                borderRadius: BorderRadius.circular(Dimens.rChip),
              ),
              child: Icon(v.icon, color: v.tint, size: 30),
            ),
            const Spacer(),
            Text(peer.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body),
            const SizedBox(height: 4),
            Row(
              children: [
                StatusDot(online: peer.online, size: 7),
                const SizedBox(width: 6),
                Text(peer.online ? 'Online' : 'Offline',
                    style: AppTypography.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
