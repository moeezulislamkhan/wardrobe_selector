import 'package:flutter/material.dart';

class WardrobeScreen extends StatelessWidget {
  const WardrobeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My wardrobe')),
      body: const _FeaturePlaceholder(
        icon: Icons.checkroom_outlined,
        title: 'Your wardrobe starts here',
        description:
            'Clothing items and their photos will be stored on this device.',
      ),
    );
  }
}

class _FeaturePlaceholder extends StatelessWidget {
  const _FeaturePlaceholder({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
