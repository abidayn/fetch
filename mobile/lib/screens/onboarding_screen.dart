import 'package:flutter/material.dart';

/// First launch, before an account: two pages.
///  1. "How to use Fetch": the whole loop (Save → Organize → Find) before
///     asking for anything. The real app will play a screen recording here;
///     until it exists, a labelled placeholder per step.
///  2. "Save from any app": the one gesture everything depends on (Share,
///     then Fetch), with screenshot placeholders.
class OnboardingScreen extends StatefulWidget {
  /// Continue to account creation ([login] false) or log in ([login] true).
  final void Function({required bool login}) onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  int _step = 0; // Save / Organize / Find on page 1

  static const _steps = ['Save', 'Organize', 'Find'];
  static const _captions = [
    'Share any link to Fetch. Pick a folder, or let Fetch pick.',
    'Fetch reads it, writes a title and summary, and files it.',
    'Describe what you remember. Fetch finds it and answers from your saves.',
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _placeholder(ThemeData theme, String label, {double height = 280}) => Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      );

  Widget _dots(ThemeData theme) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < 2; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            ),
          ),
      ]);

  Widget _howTo(ThemeData theme) => ListView(padding: const EdgeInsets.all(24), children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => widget.onDone(login: false), child: const Text('Get started')),
        ),
        Text('How to use Fetch', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('Save links from any app. Fetch organises them, then finds them when you describe what you remember.',
            style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        _placeholder(theme, 'Screen recording: ${_steps[_step]}\n(Fetch on Android)'),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: [for (var i = 0; i < 3; i++) ButtonSegment(value: i, label: Text(_steps[i]))],
          selected: {_step},
          onSelectionChanged: (s) => setState(() => _step = s.first),
        ),
        const SizedBox(height: 12),
        Text(_captions[_step], textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
      ]);

  Widget _saveFromAnyApp(ThemeData theme) {
    Widget step(int n, String title, String sub) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('$n')),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub),
        );
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 40),
      Text('Save from any app', style: theme.textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text('Fetch lives in your share menu, so saving never means copying and pasting.',
          style: theme.textTheme.bodyLarge),
      const SizedBox(height: 16),
      step(1, 'Tap Share', 'In TikTok, YouTube, Instagram or your browser.'),
      step(2, 'Choose Fetch', "It's saved the moment you tap."),
      step(3, 'Pick a folder, or let Fetch pick', 'Then carry on scrolling. Fetch keeps working.'),
      const SizedBox(height: 12),
      Row(children: [
        for (final s in ['Share button in TikTok', 'Fetch in the share menu', 'Folder picker'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _placeholder(theme, 'Screenshot:\n$s', height: 160),
            ),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (p) => setState(() => _page = p),
              children: [_howTo(theme), _saveFromAnyApp(theme)],
            ),
          ),
          _dots(theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: _page == 0
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                      child: const Text('Next'),
                    ),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FilledButton(onPressed: () => widget.onDone(login: false), child: const Text('Create account')),
                    TextButton(onPressed: () => widget.onDone(login: true), child: const Text('I already have an account')),
                  ]),
          ),
        ]),
      ),
    );
  }
}
