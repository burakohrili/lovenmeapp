import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Community Guidelines Page - Topluluk Kuralları Sayfası
/// 
/// Apple Guideline 1.2.0 (User Safety) gereksinimi için oluşturuldu.
/// 
/// İçerik:
/// - Davranış kuralları
/// - Yasaklı içerikler
/// - Moderasyon politikası
/// - Ceza sistemi
/// - İletişim bilgileri
class CommunityGuidelinesPage extends StatelessWidget {
  const CommunityGuidelinesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Topluluk Kuralları',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 32),

            // 1. Hoş Geldiniz
            _buildSection(
              icon: Icons.favorite,
              iconColor: Colors.red,
              title: 'LoveNMe Topluluğuna Hoş Geldiniz',
              content: 
                'LoveNMe, gerçek mekanlar etrafında yerel topluluk keşfi ve güvenli sosyal bağlantılar sağlayan venue-based community platformudur. '
                'Topluluğumuzun güvenli ve saygılı kalması için '
                'aşağıdaki kurallara uymak zorundasınız.',
            ),
            const SizedBox(height: 24),

            // 2. Davranış Kuralları
            _buildSection(
              icon: Icons.handshake,
              iconColor: Colors.blue,
              title: 'Davranış Kuralları',
              content: '',
            ),
            _buildRulesList([
              '✓ Saygılı olun: Tüm kullanıcılara saygı ve nezaketle yaklaşın',
              '✓ Dürüst olun: Gerçek bilgilerinizi paylaşın, sahte profil oluşturmayın',
              '✓ Güvenli olun: Kişisel bilgilerinizi koruyun, şüpheli davranışları bildirin',
              '✓ Pozitif olun: Olumlu ve destekleyici bir ortam yaratın',
              '✓ Gizliliğe saygı gösterin: Başkalarının fotoğraf ve bilgilerini izinsiz paylaşmayın',
              '✓ Yasalara uyun: Türkiye Cumhuriyeti yasalarına ve yerel düzenlemelere uyun',
            ]),
            const SizedBox(height: 24),

            // 3. Yasaklı İçerikler
            _buildSection(
              icon: Icons.block,
              iconColor: Colors.red,
              title: 'Kesinlikle Yasak Olan Davranışlar',
              content: 'Aşağıdaki davranışlar kesinlikle yasaktır ve hesabınızın kalıcı olarak kapatılmasına neden olabilir:',
            ),
            _buildRulesList([
              '✗ Sahte profil oluşturmak veya kimliğinizi gizlemek',
              '✗ Taciz, tehdit veya zorbalık',
              '✗ Uygunsuz, cinsel veya müstehcen içerik paylaşmak',
              '✗ Spam mesajlar göndermek veya reklam yapmak',
              '✗ Dolandırıcılık, finansal istismar veya para talep etmek',
              '✗ Nefret söylemi, ayrımcılık veya şiddet içeren içerik',
              '✗ 18 yaşından küçük bireyleri hedef almak',
              '✗ Bot, script veya otomatik araçlar kullanmak',
              '✗ Başkalarının hesaplarını çalmak veya taklit etmek',
              '✗ Yasadışı aktiviteler organize etmek',
            ]),
            const SizedBox(height: 24),

            // 4. İçerik Moderasyonu
            _buildSection(
              icon: Icons.security,
              iconColor: Colors.green,
              title: 'İçerik Moderasyonu',
              content: 
                // Bu metin gerçekte olmayan üç şeyi vaat ediyordu: fotoğraf
                // onay süreci, otomatik içerik tespiti ve 7/24 moderasyon.
                // Hiçbiri kodda yok. Karşılıksız bir güvenlik vaadi, özelliğin
                // eksikliğinden daha büyük bir sorumluluk doğurur; metin
                // gerçekte yapılana çekildi.
                'LoveNMe uygulamasında güvenlik, kullanıcı bildirimlerine '
                'dayanır:\n\n'
                '• Her profil ve sohbetten şikâyet edebilirsin\n'
                '• Şikâyetler ekibimize iletilir ve elle incelenir\n'
                '• İstediğin kişiyi engelleyebilirsin; engellediğin kişi sana '
                'bağlantı isteği gönderemez\n'
                '• Tekrarlayan ihlaller hesabın askıya alınmasıyla sonuçlanır',
            ),
            const SizedBox(height: 24),

            // 5. Şikayet Süreci
            _buildSection(
              icon: Icons.flag,
              iconColor: Colors.orange,
              title: 'İhlal Bildirme',
              content: 
                'Bir kullanıcının bu kurallara uymadığını düşünüyorsanız, '
                'lütfen bize bildirin:\n\n'
                '1. Kullanıcı profili veya chat ekranındaki "Şikayet Et" butonuna basın\n'
                '2. İhlal nedenini seçin (Sahte Profil, Taciz, Uygunsuz İçerik, Spam)\n'
                '3. Şikayetiniz ekibimize iletilir\n'
                '4. En kısa sürede incelenir\n'
                '5. Gerekli aksiyonlar alınır',
            ),
            const SizedBox(height: 24),

            // 6. Ceza Politikası
            _buildSection(
              icon: Icons.gavel,
              iconColor: Colors.deepOrange,
              title: 'Ceza Politikası',
              content: 'İhlaller şiddetine göre aşağıdaki şekilde cezalandırılır:',
            ),
            _buildPenaltyCard(
              level: 'Seviye 1: Uyarı',
              color: Colors.yellow.shade700,
              description: 'İlk küçük ihlallerde uyarı gönderilir. Davranışınızı düzeltmeniz beklenir.',
            ),
            const SizedBox(height: 12),
            _buildPenaltyCard(
              level: 'Seviye 2: Geçici Uzaklaştırma',
              color: Colors.orange,
              description: 'Tekrarlayan ihlallerde hesabınız 7-30 gün askıya alınır.',
            ),
            const SizedBox(height: 12),
            _buildPenaltyCard(
              level: 'Seviye 3: Kalıcı Yasaklama',
              color: Colors.red,
              description: 'Ciddi veya tekrarlayan ihlallerde hesabınız kalıcı olarak kapatılır.',
            ),
            const SizedBox(height: 24),

            // 7. İtiraz Süreci
            _buildSection(
              icon: Icons.support_agent,
              iconColor: Colors.purple,
              title: 'İtiraz ve Destek',
              content: 
                'Bir karara itiraz etmek veya yardım almak için bizimle iletişime geçebilirsiniz:\n\n'
                '• Email: support@lovenme.app\n'
                '• Yanıt süresi: 24-48 saat\n'
                '• İtirazlar incelenir ve adil bir şekilde değerlendirilir',
            ),
            const SizedBox(height: 24),

            // 8. Güvenlik İpuçları
            _buildSection(
              icon: Icons.lightbulb,
              iconColor: Colors.amber,
              title: 'Güvenlik İpuçları',
              content: '',
            ),
            _buildRulesList([
              '💡 İlk buluşmalarınızı halka açık yerlerde yapın',
              '💡 Tanımadığınız kişilere para göndermeyin',
              '💡 Kişisel bilgilerinizi (adres, banka bilgileri) paylaşmayın',
              '💡 Şüpheli davranışları hemen bildirin',
              '💡 Çok hızlı ilerleyen ilişkilerden kaçının',
              '💡 Başka platformlara geçme tekliflerini reddedın',
            ]),
            const SizedBox(height: 24),

            // 9. Güncellemeler
            _buildSection(
              icon: Icons.update,
              iconColor: Colors.teal,
              title: 'Kurallar Güncellenir',
              content: 
                'Bu topluluk kuralları zaman zaman güncellenebilir. Önemli değişiklikler '
                'size bildirilecektir. Platformu kullanmaya devam ederek güncel kurallara '
                'uymayı kabul etmiş olursunuz.',
            ),
            const SizedBox(height: 32),

            // Footer - İletişim
            _buildContactFooter(context),
            const SizedBox(height: 32),

            // Son güncelleme tarihi
            Center(
              child: Text(
                'Son Güncelleme: 9 Aralık 2024',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.pink.shade400, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shield,
              size: 40,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Güvenli Topluluk',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Saygı, güven ve bağlantı',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              height: 1.6,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRulesList(List<String> rules) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rules.map((rule) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    rule,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPenaltyCard({
    required String level,
    required Color color,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                level,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.email, color: Colors.blue, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Sorularınız mı var?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Destek ekibimiz size yardımcı olmak için burada',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _sendEmail(),
            icon: const Icon(Icons.send),
            label: const Text('support@lovenme.app'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@lovenme.app',
      query: 'subject=Topluluk Kuralları Hakkında',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      }
    } catch (e) {
      // Email açılamazsa sessizce hata yakala
    }
  }
}
