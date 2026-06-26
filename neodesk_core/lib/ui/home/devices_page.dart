import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../files/file_transfer_page.dart';
import '../session/remote_session_page.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/peer_card.dart';
import '../widgets/pill_button.dart';
import '../widgets/section_header.dart';

/// Home tab: connect bar + favourites shelf + recent list + lan.
/// See DESIGN.md §4.1.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.core});

  final NeodeskCore core;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _idCtrl = TextEditingController();
  final _idFocus = FocusNode();
  bool _lanExpanded = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await widget.core.scanQrCode(context);
    final id = code?.trim();
    if (id != null && id.isNotEmpty) {
      setState(() => _idCtrl.text = id);
      _idFocus.requestFocus();
    }
  }

  void _connect(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final session = widget.core.sessions.create();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemoteSessionPage(
        core: widget.core,
        session: session,
        peerId: trimmed,
      ),
    ));
    session.connect(id: trimmed);
  }

  void _openFiles(String id) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FileTransferPage(core: widget.core, peerId: id),
    ));
  }

  Future<void> _renamePeer(PeerEntry peer) async {
    final ctrl = TextEditingController(text: peer.alias);
    final alias = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Rename device')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: peer.id),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr('Save'))),
        ],
      ),
    );
    if (alias != null) widget.core.peers.setAlias(peer.id, alias);
  }

  void _peerMenu(PeerEntry peer) {
    showAppSheet(
      context,
      (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Dimens.s16),
              child: Row(children: [
                Text(peer.displayName, style: AppTypography.title),
              ]),
            ),
            _sheetItem(
                ctx, Icons.cast, tr('Remote control'), () => _connect(peer.id)),
            _sheetItem(ctx, Icons.folder_outlined, tr('File transfer'),
                () => _openFiles(peer.id)),
            _sheetItem(ctx, Icons.terminal, tr('Terminal'),
                () => widget.core.openTerminal(context, peer.id)),
            _sheetItem(ctx, Icons.star_outline, tr('Add to favorites'),
                () => widget.core.peers.addFavorite(peer.id)),
            _sheetItem(ctx, Icons.drive_file_rename_outline, tr('Rename'),
                () => _renamePeer(peer)),
            _sheetItem(ctx, Icons.delete_outline, tr('Delete'), () {
              widget.core.peers.forget(peer.id);
            }, danger: true),
            const SizedBox(height: Dimens.s8),
          ],
        ),
    );
  }

  Widget _sheetItem(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? AppColors.danger : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: AppTypography.body.copyWith(color: color)),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverToBoxAdapter(child: _connectBar()),
          SliverToBoxAdapter(child: _favoritesShelf()),
          SliverToBoxAdapter(child: SectionHeader(title: tr('Recent'))),
          _recentList(),
          SliverToBoxAdapter(child: _lanSection()),
          const SliverToBoxAdapter(child: SizedBox(height: Dimens.s32)),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.pageInset, Dimens.s16, Dimens.s8, 0),
        child: Row(
          children: [
            Text(tr('Devices'), style: AppTypography.display),
            const Spacer(),
            IconButton(
                onPressed: _scan,
                tooltip: tr('Scan device QR'),
                icon: const Icon(Icons.qr_code_scanner)),
            IconButton(
                onPressed: () => _idFocus.requestFocus(),
                tooltip: tr('Enter ID'),
                icon: const Icon(Icons.add)),
          ],
        ),
      );

  Widget _connectBar() => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.pageInset, Dimens.s12, Dimens.pageInset, 0),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgInput,
                  borderRadius: BorderRadius.circular(Dimens.rPill),
                ),
                padding: const EdgeInsets.symmetric(horizontal: Dimens.s16),
                child: TextField(
                  controller: _idCtrl,
                  focusNode: _idFocus,
                  style: AppTypography.mono,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _connect,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: tr('Enter device ID'),
                    hintStyle: const TextStyle(color: AppColors.textDisabled),
                    icon: const Icon(Icons.search,
                        color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Dimens.s12),
            PillButton(
                label: tr('Connect'), onPressed: () => _connect(_idCtrl.text)),
          ],
        ),
      );

  Widget _favoritesShelf() => StreamBuilder<List<PeerEntry>>(
        stream: widget.core.peers.favorites,
        builder: (context, snap) {
          final items = snap.data ?? const [];
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: tr('Favorites')),
              SizedBox(
                height: 148,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Dimens.pageInset),
                  itemCount: items.length,
                  itemBuilder: (_, i) => PeerShelfCard(
                    peer: items[i],
                    onTap: () => _connect(items[i].id),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget _recentList() => StreamBuilder<List<PeerEntry>>(
        stream: widget.core.peers.recent,
        builder: (context, snap) {
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.s24),
                child: Center(
                    child: Text(tr('No recent connections yet'),
                        style: AppTypography.caption)),
              ),
            );
          }
          return SliverList.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => PeerListTile(
              peer: items[i],
              onTap: () => _connect(items[i].id),
              onMenu: () => _peerMenu(items[i]),
            ),
          );
        },
      );

  Widget _lanSection() => StreamBuilder<List<PeerEntry>>(
        stream: widget.core.peers.lan,
        builder: (context, snap) {
          final items = snap.data ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: tr('LAN devices'),
                trailing: IconButton(
                  icon: Icon(
                      _lanExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _lanExpanded = !_lanExpanded),
                ),
              ),
              if (_lanExpanded)
                ...items.map((p) => PeerListTile(
                      peer: p,
                      onTap: () => _connect(p.id),
                      onMenu: () => _peerMenu(p),
                    )),
            ],
          );
        },
      );
}
