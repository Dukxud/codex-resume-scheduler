part of 'main.dart';

/// A view of the existing shared Codex owner. Never launches another writer.
class InteractiveOwnerPanel extends StatefulWidget {
  const InteractiveOwnerPanel({
    super.key, required this.snapshot,
    required this.onReply, required this.onSteer,
    required this.onMessage, required this.onFinish,
  });
  final Map<String, dynamic> snapshot;
  final Future<void> Function(String id, Map<String, dynamic> response) onReply;
  final Future<void> Function(String text) onSteer;
  final Future<void> Function(String text) onMessage;
  final Future<void> Function() onFinish;

  @override
  State<InteractiveOwnerPanel> createState() => _InteractiveOwnerPanelState();
}

class _InteractiveOwnerPanelState extends State<InteractiveOwnerPanel> {
  final Map<String, String> _answers = {};
  final TextEditingController _steer = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _steer.dispose();
    super.dispose();
  }

  Future<void> _send(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitQuestions(Map<String, dynamic> prompt,
      List<Map<String, dynamic>> questions) async {
    final id = stringField(prompt, 'id');
    final answers = <String, dynamic>{};
    for (final q in questions) {
      final questionId = stringField(q, 'id');
      final entered = (_answers[id + ':' + questionId] ?? '').trim();
      final options = recordList(field(q, 'options'));
      final matched = options.any((o) => stringField(o, 'label') == entered);
      if (entered.isNotEmpty && options.isNotEmpty && !matched &&
          field(q, 'isOther') != true) {
        setState(() => _error = 'Choose a listed answer for ' + questionId);
        return;
      }
      answers[questionId] = {
        'answers': entered.isEmpty ? <String>[] :
          <String>[matched ? entered : 'user_note: ' + entered],
      };
    }
    await _send(() => widget.onReply(id, {'answers': answers}));
  }

  Widget _prompt(Map<String, dynamic> prompt) {
    final id = stringField(prompt, 'id');
    final method = stringField(prompt, 'method');
    final raw = field(prompt, 'params');
    final params = raw is Map
      ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final questions = recordList(field(params, 'questions'));
    final approval = method == 'item/commandExecution/requestApproval' ||
      method == 'item/fileChange/requestApproval';
    final isQuestion = method == 'item/tool/requestUserInput' ||
      method == 'tool/requestUserInput';
    final command = field(params, 'command');
    final commandText = command is String ? command :
      command is List ? command.join(' ') : '';
    return Container(
      key: Key('interactive-prompt-' + id),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff29293f),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeckColor.gold)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CODEX NEEDS YOUR INPUT',
          style: TextStyle(color: DeckColor.gold,
            fontWeight: FontWeight.w800, fontSize: 11)),
        if (stringField(params, 'reason').isNotEmpty)
          SelectableText(stringField(params, 'reason'),
            style: const TextStyle(color: DeckColor.text)),
        if (commandText.isNotEmpty)
          SelectableText(commandText, style: const TextStyle(
            color: DeckColor.aqua, fontSize: 11, fontFamily: 'Consolas')),
        if (approval) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              key: Key('interactive-decline-' + id),
              onPressed: _busy ? null :
                () => _send(() => widget.onReply(id, {'decision': 'decline'})),
              child: const Text('Decline')),
            FilledButton(
              key: Key('interactive-approve-' + id),
              onPressed: _busy ? null :
                () => _send(() => widget.onReply(id, {'decision': 'accept'})),
              child: const Text('Approve')),
          ]),
        ] else if (isQuestion) ...[
          for (final question in questions) ...[
            const SizedBox(height: 8),
            Text(stringField(question, 'question'),
              style: const TextStyle(color: DeckColor.text)),
            TextField(
              key: Key('interactive-question-' + stringField(question, 'id')),
              onChanged: (v) =>
                _answers[id + ':' + stringField(question, 'id')] = v,
              decoration: InputDecoration(isDense: true,
                hintText: recordList(field(question, 'options'))
                  .map((o) => stringField(o, 'label')).join(' / '))),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('interactive-submit-answers'),
            onPressed: _busy ? null :
              () => _submitQuestions(prompt, questions),
            child: const Text('Send answers')),
        ] else if (method == 'mcpServer/elicitation/request') ...[
          const Text('A connected service requests structured input.',
            style: TextStyle(color: DeckColor.text)),
          OutlinedButton(
            onPressed: _busy ? null : () => _send(() =>
              widget.onReply(id, {'action': 'decline', 'content': null})),
            child: const Text('Decline request')),
        ] else ...[
          Text('Unsupported request format: ' + method,
            style: const TextStyle(color: DeckColor.gold)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompts = recordList(field(widget.snapshot, 'pending'));
    final events = recordList(field(widget.snapshot, 'events'));
    final text = StringBuffer();
    for (final event in events) {
      if (stringField(event, 'method') != 'item/agentMessage/delta') continue;
      final raw = field(event, 'params');
      if (raw is Map) {
        text.write(stringField(Map<String, dynamic>.from(raw), 'delta'));
      }
    }
    final phase = stringField(widget.snapshot, 'phase');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.forum_outlined, size: 17, color: DeckColor.aqua),
        const SizedBox(width: 8),
        Expanded(child: Text(prompts.isNotEmpty
          ? 'WAITING FOR YOUR ANSWER'
          : 'SHARED CODEX · ' + phase.toUpperCase(),
          style: const TextStyle(color: DeckColor.aqua,
            fontWeight: FontWeight.w800, fontSize: 11))),
      ]),
      if (text.isNotEmpty) ...[
        const SizedBox(height: 8),
        SelectableText(text.toString(),
          style: const TextStyle(color: DeckColor.text, fontSize: 12)),
      ],
      for (final prompt in prompts) _prompt(prompt),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: DeckColor.gold)),
      if ((phase == 'running' || phase == 'awaitingUser') && prompts.isEmpty) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            key: const Key('interactive-steer-text'),
            controller: _steer,
            decoration: const InputDecoration(
              hintText: phase == 'awaitingUser'
                ? 'Reply to Codex in this conversation' : 'Message this running turn',
              isDense: true))),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('interactive-steer'),
            onPressed: _busy ? null : () => _send(() async {
              final text = _steer.text.trim();
              if (text.isEmpty) return;
              if (phase == 'awaitingUser') {
                await widget.onMessage(text);
              } else {
                await widget.onSteer(text);
              }
              if (mounted) _steer.clear();
            }),
            child: const Text('Send')),
        ]),
      ],
      if (phase == 'awaitingUser') ...[
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('interactive-finish'),
            onPressed: _busy ? null : () => _send(widget.onFinish),
            child: const Text('Finish session'))),
      ],
      const Divider(height: 24, color: DeckColor.line),
    ]);
  }
}
