import 'package:flutter/material.dart';
import '../../../../core/widgets/base_screen.dart';

class BankAccountPage extends StatefulWidget {
  const BankAccountPage({super.key});

  @override
  State<BankAccountPage> createState() => _BankAccountPageState();
}

class _BankAccountPageState extends State<BankAccountPage> {
  final List<Map<String, String>> _banks = [
    {'name': 'Vietcombank', 'logo': 'VCB'},
    {'name': 'Techcombank', 'logo': 'TCB'},
    {'name': 'MB Bank', 'logo': 'MB'},
    {'name': 'Agribank', 'logo': 'AGRI'},
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BaseScreen(
      title: 'Ngân hàng liên kết',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chọn ngân hàng để liên kết', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 2.5
              ),
              itemCount: _banks.length,
              itemBuilder: (context, index) {
                // HIỆU ỨNG CHUYỂN ĐỘNG Ở ĐÂY
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 400 + (index * 150)),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: _buildBankItem(_banks[index], colorScheme),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankItem(Map<String, String> bank, ColorScheme colorScheme) {
    return InkWell(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            CircleAvatar(radius: 15, child: Text(bank['logo']!, style: const TextStyle(fontSize: 10))),
            const SizedBox(width: 8),
            Text(bank['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}