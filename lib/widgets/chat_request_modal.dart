// lib/widgets/chat_request_modal.dart

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/services/chat_request_service.dart';

/// Connection request modal.
class ChatRequestModal extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final bool isSuperChat;
  final VoidCallback? onSuccess;

  const ChatRequestModal({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    this.isSuperChat = false,
    this.onSuccess,
  });

  @override
  State<ChatRequestModal> createState() => _ChatRequestModalState();
}

class _ChatRequestModalState extends State<ChatRequestModal>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  String? _selectedQuickMessage;
  bool _isLoading = false;
  bool _useCustomMessage = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  int get _remainingChars {
    return 20 - _messageController.text.length;
  }

  bool get _isMessageValid {
    if (!widget.isSuperChat) return true;
    if (_useCustomMessage) {
      return _messageController.text.trim().isNotEmpty && 
             _messageController.text.length <= 20;
    }
    return _selectedQuickMessage != null;
  }

  Future<void> _sendRequest() async {
    if (!_isMessageValid) return;

    setState(() => _isLoading = true);

    try {
      String? message;
      if (widget.isSuperChat) {
        message = _useCustomMessage 
            ? _messageController.text.trim()
            : _selectedQuickMessage;
      }

      final success = await ChatRequestService.sendChatRequest(
        toUserId: widget.targetUserId,
        isSuperChat: widget.isSuperChat,
        customMessage: message,
      );

      if (success && mounted) {
        widget.onSuccess?.call();
        Navigator.of(context).pop(true);
        
        // Başarı mesajı göster
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isSuperChat
                  ? '⭐ Öne çıkan istek gönderildi!'
                  : '💬 Chat isteği gönderildi!',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('İstek gönderilemedi. Lütfen tekrar deneyin.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bir hata oluştu'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 16,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  _buildHeader(),
                  
                  const SizedBox(height: 20),
                  
                  // Content
                  if (widget.isSuperChat)
                    _buildSuperChatContent()
                  else
                    _buildNormalChatContent(),
                  
                  const SizedBox(height: 20),
                  
                  // Buttons
                  _buildButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Title
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.isSuperChat) ...[
              const Icon(
                Icons.stars_rounded,
                size: 22,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              widget.isSuperChat ? 'Öne Çıkan İstek' : 'Bağlantı İsteği',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 10),
        
        // Subtitle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.targetUserName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNormalChatContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.info_outline,
            color: AppColors.primary,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            '${widget.targetUserName} kullanıcısına bağlantı isteği göndermek istiyor musunuz?',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Kabul ederse güvenli mesajlaşma başlayacak.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSuperChatContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode selector
        Row(
          children: [
            Expanded(
              child: _buildModeButton(
                'Hazır Notlar',
                Icons.message,
                !_useCustomMessage,
                () => setState(() => _useCustomMessage = false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeButton(
                'Kısa Not',
                Icons.edit,
                _useCustomMessage,
                () => setState(() => _useCustomMessage = true),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Content based on mode
        if (_useCustomMessage)
          _buildCustomMessageInput()
        else
          _buildQuickMessages(),
      ],
    );
  }

  Widget _buildModeButton(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? const LinearGradient(
                  colors: [
                    Color(0xFFFF6B9D),
                    Color(0xFFC239B8),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.grey300,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected ? [
            BoxShadow(
              color: const Color(0xFFC239B8).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomMessageInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kısa notunu yaz',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _remainingChars < 0 
                  ? AppColors.error 
                  : _messageController.text.isNotEmpty
                      ? const Color(0xFFC239B8)
                      : AppColors.grey300,
              width: 1.5,
            ),
            boxShadow: _messageController.text.isNotEmpty ? [
              BoxShadow(
                color: const Color(0xFFC239B8).withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _messageController,
                maxLength: 20,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Notunu buraya yaz...',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _remainingChars < 0 
                      ? AppColors.error.withOpacity(0.1)
                      : _remainingChars < 5
                          ? Colors.orange.withOpacity(0.1)
                          : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Maksimum 20 karakter',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      '$_remainingChars kalan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _remainingChars < 0 
                            ? AppColors.error 
                            : _remainingChars < 5
                                ? Colors.orange
                                : const Color(0xFFC239B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickMessages() {
    final messages = ChatRequestService.getQuickMessages();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hazır notlardan birini seç',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        ...messages.map((message) {
          final isSelected = _selectedQuickMessage == message;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedQuickMessage = message),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  gradient: isSelected 
                      ? LinearGradient(
                          colors: [
                            const Color(0xFFFF6B9D).withOpacity(0.15),
                            const Color(0xFFC239B8).withOpacity(0.15),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.white,
                  border: Border.all(
                    color: isSelected 
                        ? const Color(0xFFC239B8) 
                        : AppColors.grey300,
                    width: isSelected ? 2 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: const Color(0xFFC239B8).withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? const Color(0xFFC239B8)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected 
                              ? const Color(0xFFC239B8)
                              : AppColors.grey300,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 14,
                          color: isSelected 
                              ? const Color(0xFFC239B8)
                              : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        // İptal
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppColors.grey300, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'İptal',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Gönder
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              gradient: widget.isSuperChat && _isMessageValid
                  ? const LinearGradient(
                      colors: [
                        Color(0xFFFF6B9D),
                        Color(0xFFC239B8),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: widget.isSuperChat && _isMessageValid ? [
                BoxShadow(
                  color: const Color(0xFFC239B8).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ] : null,
            ),
            child: ElevatedButton(
              onPressed: (_isLoading || !_isMessageValid) ? null : _sendRequest,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: widget.isSuperChat 
                    ? Colors.transparent
                    : AppColors.secondary,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isSuperChat ? Icons.stars_rounded : Icons.send_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isSuperChat ? 'Öne Çıkan İstek Gönder' : 'İstek Gönder',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Helper function to show modal
Future<bool?> showChatRequestModal({
  required BuildContext context,
  required String targetUserId,
  required String targetUserName,
  bool isSuperChat = false,
  VoidCallback? onSuccess,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ChatRequestModal(
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      isSuperChat: isSuperChat,
      onSuccess: onSuccess,
    ),
  );
}
