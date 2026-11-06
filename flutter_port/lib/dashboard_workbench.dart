part of 'main.dart';

/// Conversation, checkout, model and safety boundary in one deliberate step.
extension _DashboardWorkbench on _SchedulerHomeState {
  Widget _sourceCard(SchedulerController state) {
    final modelOptions = state.models.map((model) {
      final id = stringField(model, 'id');
      final caption = stringField(model, 'name');
      return DropdownMenuItem<String>(
        value: id,
        child: Text(caption.isEmpty ? id : caption,
          overflow: TextOverflow.ellipsis, maxLines: 1),
      );
    }).toList();
    final validModel = state.models.any(
      (entry) => stringField(entry, 'id') == state.model);
    final choices = state.sessions.map((item) => DropdownMenuItem<String>(
      value: stringField(item, 'Id'),
      child: Text(stringField(item, 'Display'),
        overflow: TextOverflow.ellipsis, maxLines: 1),
    )).toList();

    return DeckSurface(
      top: const Color(0xff1a3542), bottom: const Color(0xff182235),
      accent: DeckColor.mint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DeckOverline('01  /  CONNECTION', color: DeckColor.mint),
        const SizedBox(height: 5),
        const Text('Choose your thread',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800,
            color: DeckColor.text, letterSpacing: -.45)),
        const SizedBox(height: 11),
        _deckFieldLabel('CONVERSATION'),
        const SizedBox(height: 5),
        SizedBox(height: 42, child: DeckSelect<String>(
          name: 'session', value: state.sessions.any((entry) =>
            stringField(entry, 'Id') == state.sessionId)
              ? state.sessionId : null,
          items: choices,
          onChanged: (id) {
            repository.clear();
            state.selectSession(id);
          },
        )),
        const SizedBox(height: 9),
        _deckFieldLabel('REPOSITORY'),
        const SizedBox(height: 5),
        SizedBox(height: 43, child: Row(children: [
          Expanded(child: DeckField(
            fieldKey: const Key('repository-root-field'),
            controller: repository,
            hint: 'Select a verified checkout',
            onChanged: (value) => state.edit(repository: value),
          )),
          const SizedBox(width: 9),
          DeckAction(label: 'Browse', icon: Icons.folder_open_outlined,
            tone: DeckColor.mint, compact: true, onTap: _browseRepo),
        ])),
        const SizedBox(height: 9),
        Row(children: [
          Expanded(flex: 5, child: _deckSelectField(
            'MODEL',
            DeckSelect<String>(
              name: 'model',
              value: validModel ? state.model : null,
              items: modelOptions,
              onChanged: state.selectModel,
            ),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: _deckSelectField(
            'THINKING',
            DeckSelect<String>(
              name: 'effort',
              value: state.efforts.contains(state.effort)
                ? state.effort : null,
              items: state.efforts.map((effort) => DropdownMenuItem<String>(
                value: effort,
                child: Text(effort, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (choice) {
                if (choice != null) state.edit(reasoning: choice);
              },
            ),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 4, child: _deckSelectField(
            'PERMISSION',
            DeckSelect<String>(
              name: 'access', value: state.access,
              items: const [
                DropdownMenuItem(value: 'workspace-write',
                  child: Text('Workspace write')),
                DropdownMenuItem(value: 'read-only',
                  child: Text('Read-only test')),
                DropdownMenuItem(value: 'yolo',
                  child: Text('Full access (YOLO)')),
              ],
              onChanged: (choice) {
                if (choice != null) state.edit(accessMode: choice);
              },
            ),
          )),
        ]),
        if (state.repositoryWarning != null) ...[
          const SizedBox(height: 4),
          Text(state.repositoryWarning!, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: DeckColor.gold)),
        ],
      ]),
    );
  }

  Widget _deckSelectField(String caption, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _deckFieldLabel(caption),
      const SizedBox(height: 5),
      SizedBox(height: 42, child: child),
    ],
  );

  Widget _deckFieldLabel(String label) => Text(label,
    maxLines: 1, overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: DeckColor.muted, fontSize: 10,
      fontWeight: FontWeight.w700, letterSpacing: 1.3));

  /// The handoff is a single decision: an exact moment and a written intent.
  Widget _launchCard(SchedulerController state) {
    final resetAt = state.resetSuggestion;
    final date = state.runAt;
    return DeckSurface(
      top: const Color(0xff4b2a43),
      bottom: const Color(0xff292642),
      accent: DeckColor.coral,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
      // The glow must flow through the inset padding. DeckSurface's outer
      // rounded clip still contains it; Stack's default rectangular clip
      // would leave hard edges at the top and right of the content bounds.
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(right: -72, top: -138,
          child: IgnorePointer(child: Container(width: 290, height: 290,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                DeckColor.coral.withValues(alpha: .31),
                DeckColor.rose.withValues(alpha: .13),
                DeckColor.rose.withValues(alpha: 0),
              ]),
            ),
          ))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: DeckOverline('02  /  THE HANDOFF',
              color: DeckColor.gold)),
            const DeckInfo('SECOND-PRECISE', color: DeckColor.gold,
              icon: Icons.schedule_rounded),
          ]),
          const SizedBox(height: 5),
          const Text('Set the moment.',
            style: TextStyle(fontSize: 25, height: 1.1,
              fontWeight: FontWeight.w800, color: DeckColor.text,
              letterSpacing: -.6)),
          const SizedBox(height: 10),
          SizedBox(height: 61, child: Center(child: SizedBox(
            height: 40,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 38, child: DeckAction(
              label: '−', tone: DeckColor.gold, compact: true,
              onTap: () => state.edit(time: stepRunAt(state.runAt, -1)))),
            const SizedBox(width: 8),
            Expanded(child: Material(
              color: const Color(0xff221c36).withValues(alpha: .95),
              borderRadius: BorderRadius.circular(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: Tooltip(
                    message: 'Choose date',
                    child: InkWell(
                      key: const Key('scheduled-date-picker'),
                      onTap: pickDate,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 6),
                        child: Row(children: [
                          const Icon(Icons.calendar_month_rounded,
                            size: 19, color: DeckColor.gold),
                          const SizedBox(width: 10),
                          Expanded(child: Text(formatDayMonth(date, year: true),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: DeckColor.text, fontSize: 17,
                              fontWeight: FontWeight.w800))),
                        ]),
                      ),
                    ),
                  )),
                  Tooltip(
                    message: 'Type time',
                    child: InkWell(
                      key: const Key('scheduled-time-picker'),
                      onTap: pickTime,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(child: Text(
                          formatLocalClock(date, seconds: true),
                          key: const Key('selected-run-time-label'),
                          maxLines: 1,
                          style: const TextStyle(color: DeckColor.gold,
                            fontSize: 15.5, fontWeight: FontWeight.w700),
                        )),
                      ),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 38, child: DeckAction(
              label: '+', tone: DeckColor.gold, compact: true,
              onTap: () => state.edit(time: stepRunAt(state.runAt, 1)))),
            const SizedBox(width: 8),
            SizedBox(width: 108, child: DeckAction(
              label: resetAt == null ? 'Now +1' : 'Reset +1',
              tone: DeckColor.coral, compact: true,
              onTap: () => state.edit(
                time: resetAt ?? suggestedRunAt()))),
            ]),
          ))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _deckFieldLabel('INSTRUCTION FOR CODEX')),
            PopupMenuButton<String>(
              key: const Key('execution-mode-picker'),
              tooltip: 'How Codex will run',
              initialValue: state.executionMode,
              onSelected: (value) => state.edit(executionMode: value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'interactive',
                  child: Text('Interactive · questions and approvals')),
                PopupMenuItem(value: 'unattended',
                  child: Text('Unattended · no interactive questions')),
              ],
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(state.executionMode == 'interactive'
                  ? Icons.chat_bubble_outline_rounded : Icons.nightlight_outlined,
                  size: 14, color: DeckColor.aqua),
                const SizedBox(width: 5),
                Text(state.executionMode == 'interactive'
                    ? 'INTERACTIVE' : 'UNATTENDED',
                  style: const TextStyle(color: DeckColor.aqua,
                    fontSize: 10.5, fontWeight: FontWeight.w800)),
                const Icon(Icons.expand_more_rounded,
                  color: DeckColor.aqua, size: 16),
              ]),
            ),
          ]),
          const SizedBox(height: 5),
          SizedBox(height: 59, child: DeckField(
            controller: instruction,
            hint: 'What should Codex do when it resumes?',
            maxLines: 2,
            onChanged: (value) => state.edit(instruction: value),
          )),
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(
              height: 36,
              child: Switch.adaptive(
                key: const Key('auto-resume-on-limit'),
                value: state.autoResumeOnLimit,
                activeTrackColor: DeckColor.mint,
                onChanged: (value) => state.edit(autoResumeOnLimit: value),
              ),
            ),
            const SizedBox(width: 7),
            const Expanded(child: Tooltip(
              message: 'Up to 3 bounded continuations, only after a verified quota reset. Each resumes with the selected permissions.',
              child: Text('Auto-resume if usage limits stop Codex',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: DeckColor.text, fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 8),
            const DeckInfo('OPT-IN', color: DeckColor.mint),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(child: Text(
              state.canSchedule
                ? 'Windows will verify the task again at launch.'
                : 'A verified model and fresh account data are required.',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DeckColor.muted, fontSize: 10.5))),
            const SizedBox(width: 10),
            SizedBox(width: 193, child: DeckAction(
              label: 'Schedule once',
              icon: Icons.arrow_outward_rounded,
              tone: DeckColor.coral,
              primary: true, onTap: state.canSchedule ? schedule : null,
            )),
          ]),
        ]),
      ]),
    );
  }

  Future<void> _browseRepo() async {
    try {
      final result = await controller!.adapter.call('browse');
      final path = stringField(result, 'path');
      if (path.isEmpty) return;
      repository.text = path;
      controller!.edit(repository: path);
    } catch (error) {
      toast('Folder picker: ' + error.toString());
    }
  }
}
