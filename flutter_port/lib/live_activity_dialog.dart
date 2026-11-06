part of 'main.dart';

/// Read-only view of one Scheduler run. The controller already polls Windows
/// every two seconds; this dialog subscribes to that snapshot instead of
/// starting a second polling process or holding a private timer.
class LiveActivityDialog extends StatefulWidget {
  const LiveActivityDialog({
    super.key, required this.controller, required this.run,
  });

  final SchedulerController controller;
  final Map<String, dynamic> run;

  @override
  State<LiveActivityDialog> createState() => _LiveActivityDialogState();
}

class _LiveActivityDialogState extends State<LiveActivityDialog> {
  Map<String, dynamic>? _lastActivity;
  bool _showAll = false;

  String get _name => stringField(widget.run, 'Name');

  Future<void> _answerShared(String id, Map<String, dynamic> answer) async {
    try {
      await widget.controller.adapter.call('sharedAnswer', {
        'name': _name, 'questionId': id, 'answer': answer,
      });
      await widget.controller.poll();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Codex did not accept the answer: $error')));
    }
  }

  @override
  void initState() {
    super.initState();
    _lastActivity = widget.controller.activities[_name];
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    // A completed run disappears from the running-only activity poll.
    // Retain its last observed events while this dialog remains open.
    final latest = widget.controller.activities[_name];
    if (latest != null) _lastActivity = latest;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Map<String, dynamic>? _find(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      if (stringField(row, 'Name') == _name) return row;
    }
    return null;
  }

  String _stateLabel(Map<String, dynamic>? active,
      Map<String, dynamic>? historical) {
    if (active != null) return stringField(active, 'Status').toUpperCase();
    if (historical != null) {
      final status = stringField(historical, 'Status');
      return status.isEmpty ? 'RESULT AVAILABLE' : status.toUpperCase();
    }
    return 'NO LONGER IN FLIGHT';
  }

  String _age(DateTime? time) {
    if (time == null) return 'No events observed';
    final seconds = DateTime.now().difference(time).inSeconds;
    if (seconds <= 1) return 'Just now';
    if (seconds < 60) return '${seconds}s ago';
    if (seconds < 3600) return '${seconds ~/ 60}m ago';
    if (seconds < 86400) return '${seconds ~/ 3600}h ago';
    return '${seconds ~/ 86400}d ago';
  }

  String _elapsed(DateTime? start, DateTime? through) {
    if (start == null || through == null) return 'Unavailable';
    final seconds = through.difference(start).inSeconds;
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final current = _find(widget.controller.upcoming);
    final history = _find(widget.controller.history);
    final active = current != null &&
      stringField(current, 'Status') == 'Running' ? current : null;
    final status = _stateLabel(current, history);
    final nativeTerminal = stringField(widget.run, 'ExecutionMode') == 'terminal';
    final sharedMode = stringField(widget.run, 'ExecutionMode') == 'shared';
    final activity = _lastActivity;
    final rawShared = field(activity, 'Shared');
    final shared = rawShared is Map
      ? Map<String, dynamic>.from(rawShared) : <String, dynamic>{};
    final recent = field(activity, 'Recent');
    final structured = recordList(field(activity, 'Timeline'));
    final timeline = structured.isNotEmpty ? structured : [
      if (recent is List)
        for (final label in recent.whereType<String>())
          {'Label': label, 'At': null},
    ];
    final visible = timeline.reversed.take(
      _showAll ? timeline.length : 3).toList();
    final commands = field(activity, 'CompletedCommands');
    final edits = field(activity, 'FileChanges');
    final startedAt = dateField(activity, 'StartedAt');
    final updatedAt = dateField(activity, 'UpdatedAt');
    final summary = stringField(activity, 'Summary');
    final project = stringField(widget.run, 'Repo')
      .split(RegExp(r'[\\/]')).last;

    return Dialog(
      key: const Key('live-activity-dialog'),
      backgroundColor: const Color(0xff171e32),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 600,
        height: math.min(560, math.max(148,
          MediaQuery.sizeOf(context).height - 36)).toDouble(),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(17, 10, 9, 8),
            child: Row(children: [
              const Icon(Icons.track_changes_rounded,
                color: DeckColor.aqua, size: 21),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIVE ACTIVITY', style: TextStyle(
                  color: DeckColor.aqua, letterSpacing: 1.1,
                  fontSize: 10, fontWeight: FontWeight.w800)),
                Text(project.isEmpty ? 'Codex run' : project,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: DeckColor.text,
                    fontSize: 17, fontWeight: FontWeight.w800)),
              ])),
              IconButton(
                key: const Key('close-live-activity'),
                tooltip: 'Close live activity',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: DeckColor.muted)),
            ])),
          const Divider(height: 1, color: DeckColor.line),
          Expanded(child: ListView(
            key: const Key('live-activity-scroll'),
            padding: const EdgeInsets.fromLTRB(17, 12, 17, 14),
            children: [
              Wrap(spacing: 9, runSpacing: 7, children: [
                _metric('STATUS', status, active != null
                  ? DeckColor.gold : DeckColor.mint),
                _metric(active != null ? 'ACTIVE FOR' : 'OBSERVED FOR',
                  _elapsed(startedAt,
                    active != null ? DateTime.now() : updatedAt),
                  DeckColor.aqua),
                _metric('LAST EVENT', _age(updatedAt), DeckColor.iris),
              ]),
              const SizedBox(height: 13),
              const Text('LATEST ACTIVITY',
                style: TextStyle(color: DeckColor.muted,
                  fontSize: 10, fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
              const SizedBox(height: 5),
              Text(nativeTerminal
                ? 'Codex is running in its native terminal. '
                  'Switch to that window to answer questions and approvals.'
                : summary.isEmpty
                  ? 'Waiting for Codex events' : summary,
                key: const Key('live-dialog-status'),
                style: const TextStyle(color: DeckColor.text,
                  fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text('${commands is num ? commands : 0} commands · '
                '${edits is num ? edits : 0} file-change events (recent)',
                style: const TextStyle(
                  color: DeckColor.subtle, fontSize: 10.5)),
              if (sharedMode) ...[
                const SizedBox(height: 12),
                SharedQuestionsPanel(state: shared, onAnswer: _answerShared),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(child: Text('RECENT MILESTONES',
                  style: TextStyle(color: DeckColor.muted,
                    fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 1.1))),
                if (timeline.length > 3)
                  TextButton(
                    key: const Key('toggle-live-timeline'),
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll ? 'Show less'
                      : 'Show all (${timeline.length})')),
              ]),
              if (visible.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(nativeTerminal
                    ? 'The native Codex terminal owns the interactive display.'
                    : 'No milestones recorded yet.',
                    style: const TextStyle(color: DeckColor.muted))),
              for (final entry in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, size: 7,
                        color: DeckColor.aqua),
                      const SizedBox(width: 10),
                      Expanded(child: Text(stringField(entry, 'Label'),
                        style: const TextStyle(color: DeckColor.text,
                          fontSize: 11.5))),
                      if (dateField(entry, 'At') case final DateTime at)
                        Text(formatLocalClock(at, seconds: true),
                          style: const TextStyle(color: DeckColor.muted,
                            fontSize: 10)),
                    ])),
              const SizedBox(height: 8),
              Text(nativeTerminal
                ? 'Windows run state updates automatically. '
                  'The interactive terminal is the source of questions.'
                : active != null
                  ? 'Automatically updated from Windows every 2 seconds.'
                  : 'Last observed activity retained for inspection.',
                style: const TextStyle(color: DeckColor.subtle,
                  fontSize: 10)),
            ],
          )),
          const Divider(height: 1, color: DeckColor.line),
          const Padding(padding: EdgeInsets.fromLTRB(17, 8, 17, 10),
            child: Text('Activity is not a percentage-complete estimate.',
              style: TextStyle(color: DeckColor.subtle, fontSize: 10))),
        ]),
      ),
    );
  }

  Widget _metric(String label, String value, Color accent) => Container(
    constraints: const BoxConstraints(minWidth: 120),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff202942),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: accent.withValues(alpha: .28))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: DeckColor.muted,
        fontSize: 9, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: accent, fontSize: 11,
          fontWeight: FontWeight.w800)),
    ]));
}
