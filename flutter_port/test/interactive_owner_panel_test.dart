import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_resume_flutter/main.dart';

void main() {
  const approvalId = '71';
  final conversation = <String, dynamic>{
    'phase': 'awaitingInput',
    'sessionId': '11111111-2222-3333-4444-555555555555',
    'events': [
      {'type': 'notification', 'method': 'item/agentMessage/delta',
       'params': {'delta': 'I need approval to continue.'}},
    ],
    'pending': [
      {'id': approvalId, 'method': 'item/commandExecution/requestApproval',
       'params': {'reason': 'Verify local repository', 'command': 'git status'}},
    ],
  };

  testWidgets('shared owner shows Codex question and routes approval to existing owner',
      (tester) async {
    String? answeredId;
    Map<String, dynamic>? answer;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InteractiveOwnerPanel(
        snapshot: conversation,
        onReply: (id, response) async { answeredId = id; answer = response; },
        onSteer: (text) async {},
      ),
    ))));
    expect(find.text('CODEX NEEDS YOUR INPUT'), findsOneWidget);
    expect(find.text('Verify local repository'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    expect(find.textContaining('I need approval'), findsOneWidget);
    await tester.tap(find.byKey(const Key('interactive-approve-71')));
    await tester.pump();
    expect(answeredId, approvalId);
    expect(answer, {'decision': 'accept'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared owner routes a multi-question answer back to one request',
      (tester) async {
    Map<String, dynamic>? answer;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InteractiveOwnerPanel(
        snapshot: {
          'phase': 'awaitingInput',
          'events': const [],
          'pending': [
            {'id': '72', 'method': 'item/tool/requestUserInput',
             'params': {'questions': [
               {'id': 'preferred_mode', 'question': 'Which mode?',
                'options': [{'label': 'Safe'}, {'label': 'Fast'}]},
             ]}},
          ],
        },
        onReply: (id, response) async { answer = response; },
        onSteer: (text) async {},
      ),
    ))));
    await tester.enterText(
      find.byKey(const Key('interactive-question-preferred_mode')), 'Safe');
    await tester.tap(find.byKey(const Key('interactive-submit-answers')));
    await tester.pump();
    expect(answer, {
      'answers': {
        'preferred_mode': {'answers': ['Safe']},
      },
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('running shared owner can steer its existing turn',
      (tester) async {
    String? message;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: InteractiveOwnerPanel(
        snapshot: {'phase': 'running', 'pending': const [], 'events': const []},
        onReply: (id, response) async {},
        onSteer: (text) async { message = text; },
      ),
    ))));
    await tester.enterText(find.byKey(const Key('interactive-steer-text')),
      'Clarify the previous command.');
    await tester.tap(find.byKey(const Key('interactive-steer')));
    await tester.pump();
    expect(message, 'Clarify the previous command.');
    expect(tester.takeException(), isNull);
  });
}
