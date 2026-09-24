import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/item.dart';
import '../util/open_link.dart';
import 'edit_item_sheet.dart';

/// Satu baris item, dipakai di home dan hasil pencarian.
///
/// Tap = buka link di app asalnya (aksi utama). Edit / hapus ada di menu ⋮,
/// sengaja tidak di tap/long-press supaya tidak kepencet saat scroll.
/// [onChanged] dipanggil dengan item baru setelah diedit; [onDeleted]
/// setelah backend benar-benar menghapus -- pemanggil yang memperbarui list.
class ItemTile extends StatelessWidget {
  final ApiClient apiClient;
  final Item item;
  final ValueChanged<Item> onChanged;
  final ValueChanged<Item> onDeleted;
  final Widget? leading;
  final Widget? trailingInfo;

  const ItemTile({
    super.key,
    required this.apiClient,
    required this.item,
    required this.onChanged,
    required this.onDeleted,
    this.leading,
    this.trailingInfo,
  });

  Widget _subtitle() {
    if (!item.processed) {
      return const Text('Memproses…', style: TextStyle(fontStyle: FontStyle.italic));
    }
    final meta = [item.category, item.platform].whereType<String>().join(' · ');
    if (item.summary == null) {
      // Sudah diproses tapi tidak ada isi yang bisa dibaca (mis. Instagram
      // tanpa login) -- tampilkan apa adanya, bukan "memproses" selamanya.
      return Text(meta.isEmpty ? item.url : meta, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text(
      [meta, item.summary!].where((s) => s.isNotEmpty).join('\n'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _edit(BuildContext context) async {
    final updated = await showEditItemSheet(context, apiClient, item);
    if (updated == null) return;
    onChanged(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perubahan disimpan.')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus item?'),
        content: Text(item.displayTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await apiClient.deleteItem(item.id);
      onDeleted(item);
      messenger.showSnackBar(const SnackBar(content: Text('Item dihapus.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal menghapus: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      minLeadingWidth: leading == null ? null : 24,
      title: Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(),
      isThreeLine: item.processed && item.summary != null,
      onTap: () => openLink(context, item.url),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailingInfo,
          PopupMenuButton<String>(
            tooltip: 'Aksi',
            onSelected: (action) => switch (action) {
              'open' => openLink(context, item.url),
              'edit' => _edit(context),
              'delete' => _delete(context),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Buka link'))),
              PopupMenuItem(
                value: 'edit',
                // Hasil AI yang masih diproses akan menimpa editan (backend
                // juga menolak dengan 409) -- tutup pintunya dari UI.
                enabled: item.processed,
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  subtitle: item.processed ? null : const Text('Tunggu AI selesai'),
                  enabled: item.processed,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Hapus')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
