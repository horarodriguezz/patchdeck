import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import 'comment_callbacks.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import 'diff_pane.dart';

/// Lays out the visible patches side by side: one fills the width, two
/// split it in half, three or more keep half width each and overflow
/// horizontally (shift + wheel scrolls between them).
class PanesView extends StatefulWidget {
  const PanesView({
    super.key,
    required this.workspace,
    required this.selection,
    required this.mode,
    required this.callbacks,
  });

  final WorkspaceController workspace;
  final SelectionController selection;
  final DiffMode mode;
  final CommentCallbacks callbacks;

  @override
  State<PanesView> createState() => _PanesViewState();
}

class _PanesViewState extends State<PanesView> {
  final ScrollController _h = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  Widget _pane(String id, bool multi) => DiffPane(
    key: ValueKey(id),
    patchId: id,
    workspace: widget.workspace,
    selection: widget.selection,
    showName: multi,
    callbacks: widget.callbacks,
  );

  @override
  Widget build(BuildContext context) {
    final ids = widget.workspace.visiblePatchIds;
    if (ids.length == 1) return _pane(ids.first, false);
    final divider = Theme.of(context).dividerColor;
    return LayoutBuilder(
      builder: (context, c) {
        final paneWidth = (c.maxWidth / 2).floorToDouble();
        if (ids.length == 2) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _pane(ids[0], true)),
              VerticalDivider(width: 1, color: divider),
              Expanded(child: _pane(ids[1], true)),
            ],
          );
        }
        return Scrollbar(
          controller: _h,
          thumbVisibility: true,
          notificationPredicate: (n) => n.depth == 0 && n.metrics.axis == Axis.horizontal,
          child: ListView.builder(
            controller: _h,
            scrollDirection: Axis.horizontal,
            // Leave a band for the strip's own scrollbar below the panes'
            // horizontal code scrollbars.
            padding: const EdgeInsets.only(bottom: 12),
            itemExtent: paneWidth,
            itemCount: ids.length,
            itemBuilder: (context, i) => DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: divider)),
              ),
              child: _pane(ids[i], true),
            ),
          ),
        );
      },
    );
  }
}
