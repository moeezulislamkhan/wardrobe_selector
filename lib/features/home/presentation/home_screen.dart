import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Wardrobe')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Your style, made simple.', style: textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Build your wardrobe and find outfits that feel like you.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.checkroom,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  Text('Start with your wardrobe', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Add a few pieces you love. Your wardrobe stays on this '
                    'device, and you can use the app without an account.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const Text('Guest mode is ready'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Your next steps', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          const _SetupStep(
            icon: Icons.add_a_photo_outlined,
            title: 'Add clothing items',
            detail: 'Create a personal catalog from pieces you already own.',
          ),
          const SizedBox(height: 10),
          const _SetupStep(
            icon: Icons.auto_awesome_outlined,
            title: 'Discover outfit ideas',
            detail: 'Get simple, rule-based suggestions from your wardrobe.',
          ),
        ],
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(detail),
    );
  }
}
