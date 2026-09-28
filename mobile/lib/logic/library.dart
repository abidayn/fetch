// Pure rules behind the library screens: no widgets, no HTTP, so they're
// unit-tested directly (test/library_logic_test.dart).

import '../models/folder.dart';
import '../models/item.dart';

// --- "Needs you" -------------------------------------------------------------

/// Why a save is in "Needs you": what Fetch couldn't finish alone.
enum NeedReason {
  /// Fetch proposed a folder that doesn't exist yet: accept or pick another.
  suggestion,

  /// Only the link could be read: a title makes it findable by search.
  unreadable,

  /// Nobody decided where it goes (and it's not left in Unsorted on purpose).
  noFolder,
}

/// The reasons [item] needs the user, empty if none. An item still being
/// processed never needs anything yet.
Set<NeedReason> needReasons(Item item) {
  if (!item.processed) return const {};
  final reasons = <NeedReason>{};
  if (item.suggestionWaiting) reasons.add(NeedReason.suggestion);
  // Unreadable until the user writes a title themselves (classified_by 'user').
  if (!item.hasContent && !item.editedByUser) reasons.add(NeedReason.unreadable);
  // folder_by 'user' with no folder = left in Unsorted on purpose: not a need.
  // 'ai' still waiting without a suggestion = Fetch couldn't pick one.
  if (item.folderId == null && item.folderBy != 'user' && !item.suggestionWaiting) {
    reasons.add(NeedReason.noFolder);
  }
  return reasons;
}

List<Item> needsYou(List<Item> items) => items.where((it) => needReasons(it).isNotEmpty).toList();

/// "2 folder suggestions · 1 unreadable link · 3 without a folder".
String needsSummary(List<Item> items) {
  var sug = 0, thin = 0, none = 0;
  for (final it in items) {
    final r = needReasons(it);
    if (r.contains(NeedReason.suggestion)) sug++;
    if (r.contains(NeedReason.unreadable)) thin++;
    if (r.contains(NeedReason.noFolder) && !r.contains(NeedReason.unreadable)) none++;
  }
  String n(int c, String one, String many) => '$c ${c == 1 ? one : many}';
  return [
    if (sug > 0) n(sug, 'folder suggestion', 'folder suggestions'),
    if (thin > 0) n(thin, 'unreadable link', 'unreadable links'),
    if (none > 0) '$none without a folder',
  ].join(' · ');
}

// --- time --------------------------------------------------------------------

/// "Just now", "12 min ago", "Today", "3d ago", "2w ago", "4mo ago".
String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 2) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Today';
  final days = (d.inHours / 24).round();
  if (days < 7) return '${days}d ago';
  if (days < 30) return '${(days / 7).round()}w ago';
  return '${(days / 30).round()}mo ago';
}

// --- library sections -----------------------------------------------------------

const kChipFolders = 4;

/// The folder chips on home: the [kChipFolders] most recently used, where
/// "used" counts the newest save in [items] (fresher than the server's
/// last_saved_at between reloads). A selected folder outside that set takes
/// the first slot, so the chip row always shows the active filter.
List<Folder> chipFolders(List<Folder> folders, List<Item> items, String? selectedId) {
  final newest = <String, DateTime>{};
  for (final it in items) {
    final id = it.folderId;
    if (id == null) continue;
    final prev = newest[id];
    if (prev == null || it.createdAt.isAfter(prev)) newest[id] = it.createdAt;
  }
  DateTime used(Folder f) {
    final a = newest[f.id], b = f.lastUsed;
    return a != null && a.isAfter(b) ? a : b;
  }

  final sorted = [...folders]..sort((a, b) => used(b).compareTo(used(a)));
  var top = sorted.take(kChipFolders).toList();
  final selected = folders.where((f) => f.id == selectedId).firstOrNull;
  if (selected != null && !top.contains(selected)) {
    top = [selected, ...top.take(kChipFolders - 1)];
  }
  return top;
}

/// "From a while ago": up to 3 readable saves older than 14 days, the same
/// ones all day (the date is the random seed) and different tomorrow. Only
/// once there are enough saves for resurfacing to mean anything.
List<Item> fromAWhileAgo(List<Item> items, DateTime now) {
  if (items.length < 6) return const [];
  final old = items
      .where((it) => it.processed && it.hasContent && now.difference(it.createdAt).inDays > 14)
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id)); // stable before shuffling
  final seed = now.year * 10000 + now.month * 100 + now.day;
  // A small deterministic shuffle: same day -> same order.
  var x = seed;
  for (var i = old.length - 1; i > 0; i--) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    final j = x % (i + 1);
    final t = old[i];
    old[i] = old[j];
    old[j] = t;
  }
  return old.take(3).toList();
}

/// Right after a save, the newest rows go above the "From a while ago"
/// strip so the new save is on screen.
bool hasFreshSave(List<Item> items, DateTime now) =>
    items.any((it) => !it.processed || now.difference(it.createdAt).inMinutes < 10);

// --- answers -------------------------------------------------------------------

/// A piece of an AI answer: plain text, or a citation "[n]" (1-based index
/// into the answer's sources).
class AnswerPart {
  final String? text;
  final int? cite;
  const AnswerPart.text(this.text) : cite = null;
  const AnswerPart.cite(this.cite) : text = null;
}

/// Splits "Pasta [1] and toast [2]." into text and tappable citations.
/// Numbers without a matching source are dropped (the backend strips them
/// too; this is a second guard so a button never points nowhere).
List<AnswerPart> parseAnswer(String answer, int sourceCount) {
  final parts = <AnswerPart>[];
  var last = 0;
  for (final m in RegExp(r'\[(\d+)\]').allMatches(answer)) {
    if (m.start > last) parts.add(AnswerPart.text(answer.substring(last, m.start)));
    final n = int.parse(m.group(1)!);
    if (n >= 1 && n <= sourceCount) parts.add(AnswerPart.cite(n));
    last = m.end;
  }
  if (last < answer.length) parts.add(AnswerPart.text(answer.substring(last)));
  return parts;
}

/// The distinct source numbers an answer cites, in order.
List<int> citedSources(List<AnswerPart> parts) =>
    {for (final p in parts) if (p.cite != null) p.cite!}.toList()..sort();

// --- share sheet ---------------------------------------------------------------

/// The app a share most likely came from, for "Back to TikTok". Android
/// doesn't tell the receiving app who shared, so it's guessed from the link;
/// null for web pages (could be any browser) -> a plain "Go back".
String? sourceAppName(String url) => switch (platformFromUrl(url)) {
      'youtube' => 'YouTube',
      'tiktok' => 'TikTok',
      'instagram' => 'Instagram',
      _ => null,
    };
