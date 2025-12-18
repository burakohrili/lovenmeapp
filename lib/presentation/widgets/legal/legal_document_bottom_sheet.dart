import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';

class LegalDocumentBottomSheet extends StatefulWidget {
  final String documentType; // 'terms' or 'privacy'
  final String title;
  final String content;
  final VoidCallback? onAccept;
  
  const LegalDocumentBottomSheet({
    super.key,
    required this.documentType,
    required this.title,
    required this.content,
    this.onAccept,
  });

  @override
  State<LegalDocumentBottomSheet> createState() => _LegalDocumentBottomSheetState();
}

class _LegalDocumentBottomSheetState extends State<LegalDocumentBottomSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      
      // Kullanıcı en alta kadar kaydırdıysa
      if (currentScroll >= maxScroll - 50 && !_hasScrolledToBottom) {
        setState(() {
          _hasScrolledToBottom = true;
        });
      }
    }
  }

  Future<void> _recordAcceptance() async {
    if (_isAccepting) return;
    
    setState(() {
      _isAccepting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Firebase'e kabul kaydını ekle
        await FirebaseFirestore.instance
            .collection('legal_acceptances')
            .add({
          'userId': user.uid,
          'email': user.email,
          'documentType': widget.documentType,
          'documentTitle': widget.title,
          'acceptedAt': FieldValue.serverTimestamp(),
          'userAgent': 'Flutter Mobile App',
          'version': '1.0', // Döküman versiyonu
        });
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onAccept?.call();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.title} kabul edildi'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormattedContent(widget.content),
                  const SizedBox(height: 40), // Bottom scroll için extra space
                ],
              ),
            ),
          ),
          
          // Scroll indicator
          if (!_hasScrolledToBottom)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AppColors.warning.withOpacity(0.1),
              child: const Row(
                children: [
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kabul etmek için tüm metni okuyun',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Accept Button
          Container(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _hasScrolledToBottom && !_isAccepting
                  ? _recordAcceptance
                  : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isAccepting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : Text(
                      _hasScrolledToBottom 
                        ? 'Kabul Ediyorum'
                        : 'Okumaya devam edin...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Formatlanmış içerik oluşturucu
  Widget _buildFormattedContent(String content) {
    final lines = content.split('\n');
    final List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.trim().isEmpty) {
        // Boş satır - spacing
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // Ana başlık (büyük harflerle yazılmış, tek başına satırda)
      if (line.trim().toUpperCase() == line.trim() && 
          line.trim().length > 10 && 
          !line.contains(':') &&
          !line.contains('.') &&
          (i == 0 || i < lines.length - 1)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 12),
            child: Text(
              line.trim(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        );
        continue;
      }

      // Tarih bilgisi
      if (line.contains('Güncelleme:') || line.contains('Yürürlük Tarihi:')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.trim(),
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
        continue;
      }

      // Bölüm başlıkları (rakam ile başlayan)
      if (RegExp(r'^\d+\.?\s').hasMatch(line.trim()) && !line.contains(':')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              line.trim(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
        continue;
      }

      // Alt başlıklar (rakam.rakam ile başlayan veya büyük harfle başlayan kısa satırlar)
      if (RegExp(r'^\d+\.\d+\.?\s').hasMatch(line.trim()) || 
          (line.trim().length < 50 && 
           line.trim().endsWith(':') == false &&
           line.trim()[0].toUpperCase() == line.trim()[0] &&
           !line.contains('.'))) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              line.trim(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
        continue;
      }

      // Madde işaretleri (-, •, a), b), vb.)
      if (RegExp(r'^[\-•]\s').hasMatch(line.trim()) || 
          RegExp(r'^[a-z]\)\s').hasMatch(line.trim())) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.trim().startsWith('-') ? '•' : 
                  line.trim().startsWith('•') ? '•' :
                  line.trim().substring(0, 2),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.trim().substring(2).trim(),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // İletişim bilgileri
      if (line.contains('@') || 
          line.contains('Adres:') || 
          line.contains('Tel:') ||
          line.contains('E-posta:')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line.trim(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        );
        continue;
      }

      // Önemli notlar
      if (line.contains('Önemli not:') || 
          line.contains('Not:') ||
          line.contains('Dikkat:')) {
        widgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              border: const Border(
                left: BorderSide(
                  width: 4,
                  color: AppColors.warning,
                ),
              ),
            ),
            child: Text(
              line.trim(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        );
        continue;
      }

      // Normal paragraf metni
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            line.trim(),
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

// Helper function to show legal documents
Future<void> showLegalDocument({
  required BuildContext context,
  required String documentType,
  required String title,
  required String content,
  VoidCallback? onAccept,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => LegalDocumentBottomSheet(
      documentType: documentType,
      title: title,
      content: content,
      onAccept: onAccept,
    ),
  );
}
