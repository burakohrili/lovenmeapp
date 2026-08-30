// lib/presentation/pages/messages/chat_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/message_rate_limiter_service.dart';
import 'models/match_model.dart';
import 'models/message_model.dart';
import 'providers/firebase_chat_provider.dart';
import '../profile/user_profile_page.dart';
import '../../../core/services/block_service.dart';

class ChatDetailPage extends ConsumerStatefulWidget {
  final MatchModel match;

  const ChatDetailPage({
    super.key,
    required this.match,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final FlutterSoundRecorder _soundRecorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _soundPlayer = FlutterSoundPlayer();
  
  bool _isTyping = false;
  final bool _isOtherUserTyping = false;
  bool _isUploading = false;
  bool _isRecording = false;
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String? _currentlyPlayingId;
  Timer? _playbackTimer;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    
    
    // 🔧 KEYBOARD FIX: Focus listener for keyboard handling
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Klavye açıldığında mesajları en alta scroll et
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _scrollToBottom();
        });
      }
    });
    
    _initAudio();
    Future.microtask(() {
      ref.read(firebaseChatProvider.notifier).markAsRead(widget.match.id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _initAudio() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        await _soundRecorder.openRecorder();
        await _soundPlayer.openPlayer();
        
        _soundPlayer.onProgress!.listen((event) {
          if (mounted) {
            setState(() {
              _playbackPosition = event.position;
              _playbackDuration = event.duration;
            });
          }
        });
        
        setState(() {
          _isRecorderInitialized = true;
          _isPlayerInitialized = true;
        });
      }
    } catch (e) {
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    if (_isRecorderInitialized) {
      _soundRecorder.closeRecorder();
    }
    if (_isPlayerInitialized) {
      _soundPlayer.closePlayer();
    }
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _playVoiceMessage(String url, String messageId) async {
    if (!_isPlayerInitialized) return;
    
    try {
      if (_currentlyPlayingId == messageId) {
        // Durdur
        await _soundPlayer.stopPlayer();
        setState(() {
          _currentlyPlayingId = null;
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
        });
      } else {
        // Başka bir ses çalıyorsa durdur
        if (_currentlyPlayingId != null) {
          await _soundPlayer.stopPlayer();
        }
        
        // Yeni sesi oynat
        setState(() {
          _currentlyPlayingId = messageId;
        });
        
        await _soundPlayer.startPlayer(
          fromURI: url,
          codec: Codec.aacADTS,
          whenFinished: () {
            setState(() {
              _currentlyPlayingId = null;
              _playbackPosition = Duration.zero;
              _playbackDuration = Duration.zero;
            });
          },
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ses oynatılamadı'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // Diğer metodlar aynı kalacak... (önceki koddan)
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    
    if (message.isNotEmpty) {
      
      // 🛡️ RATE LIMIT KONTROLÜ: Apple Guideline 4.3.0 - Spam Prevention
      final rateLimitResult = await MessageRateLimiterService.canSendMessage();
      
      if (!rateLimitResult.canSend) {
        // Limit doldu - kullanıcıya bildir
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rateLimitResult.reason ?? 'Çok hızlı mesaj gönderiyorsunuz',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange[700],
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return; // Mesaj gönderme
      }
      
      try {
        ref.read(firebaseChatProvider.notifier).sendMessage(
          matchId: widget.match.id,
          message: message,
        );
        
        _messageController.clear();
        
        setState(() {
          _isTyping = false;
        });
        
        _focusNode.requestFocus();
        
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
        
      } catch (e) {
      }
    } else {
    }
  }

  Future<void> _toggleRecording() async {
    if (!_isRecorderInitialized) return;
    
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final directory = await getTemporaryDirectory();
      _recordingPath = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      
      await _soundRecorder.startRecorder(
        toFile: _recordingPath,
        codec: Codec.aacADTS,
      );
      
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingSeconds++;
          });
        }
      });
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ses kaydı başlatılamadı'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      
      final path = await _soundRecorder.stopRecorder();
      
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
      
      if (path != null && path.isNotEmpty) {
        await _uploadAndSendVoiceMessage(path);
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }
  }

  Future<void> _uploadAndSendVoiceMessage(String filePath) async {
    try {
      // 🛡️ RATE LIMIT KONTROLÜ: Sesli mesaj da mesaj sayılır
      final rateLimitResult = await MessageRateLimiterService.canSendMessage();
      
      if (!rateLimitResult.canSend) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rateLimitResult.reason ?? 'Çok hızlı mesaj gönderiyorsunuz'),
              backgroundColor: Colors.orange[700],
              duration: const Duration(seconds: 3),
            ),
          );
        }
        // Ses dosyasını sil
        final file = File(filePath);
        if (file.existsSync()) await file.delete();
        return;
      }
      
      setState(() => _isUploading = true);
      
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('Ses dosyası bulunamadı');
      }
      
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('voice_messages')
          .child(widget.match.id)
          .child(fileName);
      
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      
      await ref.read(firebaseChatProvider.notifier).sendMessage(
        matchId: widget.match.id,
        message: '🎤 Sesli mesaj',
        type: MessageType.voice,
        voiceUrl: downloadUrl,
      );
      
      await file.delete();
      setState(() => _isUploading = false);
      _scrollToBottom();
      
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ses mesajı gönderilemedi'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        // 🛡️ RATE LIMIT KONTROLÜ: Fotoğraf da mesaj sayılır
        final rateLimitResult = await MessageRateLimiterService.canSendMessage();
        
        if (!rateLimitResult.canSend) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(rateLimitResult.reason ?? 'Çok hızlı mesaj gönderiyorsunuz'),
                backgroundColor: Colors.orange[700],
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        
        setState(() => _isUploading = true);

        final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('chat_images')
            .child(widget.match.id)
            .child(fileName);

        final uploadTask = await storageRef.putFile(File(image.path));
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        await ref.read(firebaseChatProvider.notifier).sendMessage(
          matchId: widget.match.id,
          message: '📷 Fotoğraf',
          type: MessageType.image,
          imageUrl: downloadUrl,
        );

        setState(() => _isUploading = false);
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf gönderilemedi'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _viewProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfilePage(userId: widget.match.userId),
      ),
    );
  }

  String _formatRecordingTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Build metodları...
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(firebaseChatProvider);
    final messages = chatState.messages[widget.match.id] ?? [];

    return Scaffold(
      backgroundColor: AppColors.grey50,
      resizeToAvoidBottomInset: true, // 🔧 KEYBOARD FIX: Resize when keyboard appears
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _viewProfile,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(widget.match.profileImage),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Yas kaldirildi: sohbet basligi kisiyi demografiyle
                      // degil adiyla tanimlar.
                      widget.match.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                    Text(
                      widget.match.isOnline
                          ? 'Çevrimiçi'
                          : widget.match.lastSeen ?? 'Çevrimdışı',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.white),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _viewProfile();
                  break;
                case 'block':
                  _showBlockDialog();
                  break;
                case 'report':
                  _showReportDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: AppColors.grey600, size: 20),
                    SizedBox(width: 8),
                    Text('Profili Gör'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, color: AppColors.warning, size: 20),
                    SizedBox(width: 8),
                    Text('Engelle'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag, color: AppColors.error, size: 20),
                    SizedBox(width: 8),
                    Text('Şikayet Et'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.match.commonVenues.isNotEmpty ||
              widget.match.commonHobbies.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.primary.withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(
                    Icons.place,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ortak: ${[...widget.match.commonVenues, ...widget.match.commonHobbies].join(', ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          if (_isUploading)
            const LinearProgressIndicator(
              color: AppColors.primary,
            ),

          Expanded(
            child: messages.isEmpty
                ? _buildEmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // 🔧 KEYBOARD PADDING: Fixed bottom padding to avoid input overlap
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == chatState.currentUserId;
                      final showDate = index == 0 ||
                          messages[index - 1].dateLabel != message.dateLabel;

                      return Column(
                        children: [
                          if (showDate) _buildDateDivider(message.dateLabel),
                          _buildMessageBubble(message, isMe),
                        ],
                      );
                    },
                  ),
          ),

          if (_isOtherUserTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: NetworkImage(widget.match.profileImage),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.match.name} yazıyor...',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          if (_isRecording)
            Container(
              padding: const EdgeInsets.all(12),
              color: AppColors.error.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mic, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Ses kaydediliyor... ${_formatRecordingTime(_recordingSeconds)}',
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _stopRecording,
                    child: const Text('Gönder', style: TextStyle(color: AppColors.primary)),
                  ),
                  TextButton(
                    onPressed: () async {
                      _recordingTimer?.cancel();
                      await _soundRecorder.stopRecorder();
                      setState(() {
                        _isRecording = false;
                        _recordingSeconds = 0;
                      });
                    },
                    child: const Text('İptal', style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(8), // 🔧 KEYBOARD PADDING: Standard padding
            decoration: BoxDecoration(
              color: AppColors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppColors.primary,
                    onPressed: _showAttachmentOptions,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      maxLines: null,
                      enabled: !_isRecording,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Mesaj yaz...',
                        hintStyle: const TextStyle(color: AppColors.textPlaceholder),
                        filled: true,
                        fillColor: AppColors.grey100,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (text) {
                        final wasTyping = _isTyping;
                        _isTyping = text.isNotEmpty;
                        
                        if (wasTyping != _isTyping && mounted) {
                          setState(() {});
                        }
                      },
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _isRecording ? AppColors.error : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isTyping ? Icons.send : (_isRecording ? Icons.stop : Icons.mic),
                        color: AppColors.white,
                        size: 20,
                      ),
                      onPressed: _isTyping ? _sendMessage : _toggleRecording,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.type == MessageType.image && message.imageUrl != null)
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: AppColors.transparent,
                      child: Stack(
                        children: [
                          Center(
                            child: Image.network(message.imageUrl!),
                          ),
                          Positioned(
                            top: 40,
                            right: 20,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: AppColors.white, size: 30),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      message.imageUrl!,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 200,
                          height: 200,
                          color: AppColors.grey200,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              )
            else if (message.type == MessageType.voice && message.voiceUrl != null)
              GestureDetector(
                onTap: () => _playVoiceMessage(message.voiceUrl!, message.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withOpacity(0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _currentlyPlayingId == message.id ? Icons.pause : Icons.play_arrow,
                        color: isMe ? AppColors.white : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🎤 Sesli mesaj',
                            style: TextStyle(
                              color: isMe ? AppColors.white : AppColors.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          if (_currentlyPlayingId == message.id)
                            Text(
                              '${_formatDuration(_playbackPosition)} / ${_formatDuration(_playbackDuration)}',
                              style: TextStyle(
                                color: isMe ? AppColors.white.withOpacity(0.7) : AppColors.grey400,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? AppColors.primary : AppColors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.type == MessageType.venue && message.venueName != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppColors.white.withOpacity(0.2)
                              : AppColors.grey100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: isMe ? AppColors.white : AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                message.venueName!,
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      message.message,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.formattedTime,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.grey600,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isRead ? Icons.done_all : Icons.done,
                      size: 14,
                      color: message.isRead ? Colors.blue[300] : AppColors.grey400,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Diğer widget metodları aynı kalacak
  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: NetworkImage(widget.match.profileImage),
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.match.name} ile bağlantı kurdunuz!',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'İlk mesajı sen at 👋',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.grey600,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              _buildQuickMessage('Merhaba! 👋'),
              _buildQuickMessage('Nasılsın?'),
              _buildQuickMessage('Tanıştığımıza memnun oldum 😊'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMessage(String text) {
    return ActionChip(
      label: Text(text),
      backgroundColor: AppColors.primary.withOpacity(0.1),
      onPressed: () {
        _messageController.text = text;
        _sendMessage();
      },
    );
  }

  Widget _buildDateDivider(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.grey300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              date,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.grey300)),
        ],
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF6B46C1),
                child: Icon(Icons.camera_alt, color: Colors.white),
              ),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.photo, color: Colors.white),
              ),
              title: const Text('Galeri'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Engelle'),
        content: Text('${widget.match.name} adlı kullanıcıyı engellemek istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            // Eskiden bu buton SADECE konuşmayı siliyordu; hiçbir engelleme
            // kaydı yazılmıyordu, karşı taraf anında yeni istek
            // gönderebiliyordu. Apple Guideline 1.2 açısından da eksikti.
            onPressed: () async {
              Navigator.pop(context);
              final ok = await BlockService.block(widget.match.userId);
              if (ok) {
                await ref
                    .read(firebaseChatProvider.notifier)
                    .deleteMatch(widget.match.id);
              }
              if (!context.mounted) return;
              if (ok) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Kullanıcı engellendi'
                      : 'Engelleme başarısız oldu, tekrar dene'),
                ),
              );
            },
            child: const Text(
              'Engelle',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şikayet Et'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.match.name} adlı kullanıcıyı neden şikayet ediyorsunuz?'),
            const SizedBox(height: 16),
            ...['Sahte Profil', 'Taciz/Rahatsız Etme', 'Uygunsuz İçerik', 'Spam/Bot'].map(
              (reason) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    reason,
                    style: const TextStyle(fontSize: 14),
                  ),
                  leading: Icon(
                    _getReportReasonIcon(reason),
                    color: Colors.red,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _reportUser(reason);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  IconData _getReportReasonIcon(String reason) {
    switch (reason) {
      case 'Sahte Profil':
        return Icons.person_off;
      case 'Taciz/Rahatsız Etme':
        return Icons.warning;
      case 'Uygunsuz İçerik':
        return Icons.block;
      case 'Spam/Bot':
        return Icons.smart_toy;
      default:
        return Icons.flag;
    }
  }

  Future<void> _reportUser(String reason) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': widget.match.userId,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'chat_report',
        'status': 'pending',
        'context': 'chat_conversation',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$reason nedeniyle şikayet edildi. İnceleyeceğiz.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şikayet gönderilemedi. Lütfen tekrar deneyin.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}