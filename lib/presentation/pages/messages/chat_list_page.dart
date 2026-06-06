// lib/presentation/pages/messages/chat_list_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import 'providers/chat_provider.dart';
import 'chat_detail_page.dart';

class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final activeChats = chatState.activeChats;

    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Sohbetler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Arama özelliği
            },
          ),
        ],
      ),
      body: activeChats.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              itemCount: activeChats.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final match = activeChats[index];
                return _buildChatItem(context, ref, match);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 100,
            color: AppColors.grey300,
          ),
          SizedBox(height: 20),
          Text(
            'Henüz sohbet yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.grey700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Bağlantılarınla konuşmaya başla!',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.grey500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, WidgetRef ref, match) {
    return Dismissible(
      key: Key(match.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(
          Icons.delete,
          color: AppColors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sohbeti Sil'),
            content: Text('${match.name} ile olan sohbeti silmek istediğine emin misin?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Sil',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        ref.read(chatProvider.notifier).deleteMatch(match.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${match.name} ile sohbet silindi'),
            action: SnackBarAction(
              label: 'Geri Al',
              onPressed: () {
                // Geri alma işlemi
              },
            ),
          ),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: NetworkImage(match.profileImage),
            ),
            if (match.isOnline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          '${match.name}, ${match.age}',
          style: TextStyle(
            fontWeight: match.unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                match.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: match.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              match.timeAgo,
              style: TextStyle(
                fontSize: 12,
                color: match.unreadCount > 0
                    ? AppColors.primary
                    : AppColors.grey600,
              ),
            ),
            if (match.unreadCount > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
                child: Text(
                  match.unreadCount.toString(),
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
        onTap: () {
          ref.read(chatProvider.notifier).selectMatch(match);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailPage(match: match),
            ),
          );
        },
      ),
    );
  }
}