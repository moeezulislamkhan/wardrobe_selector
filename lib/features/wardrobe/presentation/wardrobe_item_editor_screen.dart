import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_error.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/local_wardrobe_repository.dart';
import '../data/wardrobe_image_picker.dart';
import '../data/wardrobe_image_processor.dart';
import '../data/wardrobe_sync_service.dart';
import '../domain/guest_wardrobe_item.dart';
import 'wardrobe_photo.dart';

class WardrobeItemEditorScreen extends ConsumerStatefulWidget {
  const WardrobeItemEditorScreen({this.itemId, super.key});

  final String? itemId;

  @override
  ConsumerState<WardrobeItemEditorScreen> createState() =>
      _WardrobeItemEditorScreenState();
}

class _WardrobeItemEditorScreenState
    extends ConsumerState<WardrobeItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _subcategoryController = TextEditingController();
  final _primaryColorController = TextEditingController();
  final _secondaryColorController = TextEditingController();
  final _styleTagsController = TextEditingController();
  final _occasionController = TextEditingController();
  final _seasonController = TextEditingController();
  final _brandController = TextEditingController();
  final _notesController = TextEditingController();

  Uint8List? _photoBytes;
  String? _photoError;
  String? _savedLocalId;
  String? _saveError;
  bool _isPreparingPhoto = false;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isLoadingExisting = false;
  bool _isFavorite = false;
  GuestWardrobeItem? _existingItem;

  @override
  void initState() {
    super.initState();
    final itemId = widget.itemId;
    if (itemId != null) {
      _isLoadingExisting = true;
      Future<void>(() async {
        try {
          final items = await ref.read(wardrobeItemsProvider.future);
          final item = items
              .where((candidate) => candidate.localId == itemId)
              .firstOrNull;
          if (item == null || item.isDeleted) {
            throw const AppError('This wardrobe item is no longer available.');
          }
          if (!mounted) return;
          _existingItem = item;
          _titleController.text = item.title;
          _categoryController.text = item.category;
          _subcategoryController.text = item.subcategory ?? '';
          _primaryColorController.text = item.primaryColor ?? '';
          _secondaryColorController.text = item.secondaryColor ?? '';
          _styleTagsController.text = item.styleTags.join(', ');
          _occasionController.text = item.occasionValues.join(', ');
          _seasonController.text = item.seasonValues.join(', ');
          _brandController.text = item.brand ?? '';
          _notesController.text = item.notes ?? '';
          _isFavorite = item.isFavorite;
          setState(() => _isLoadingExisting = false);
        } on Exception catch (error) {
          if (!mounted) return;
          setState(() {
            _isLoadingExisting = false;
            _saveError = _messageFor(error);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _subcategoryController.dispose();
    _primaryColorController.dispose();
    _secondaryColorController.dispose();
    _styleTagsController.dispose();
    _occasionController.dispose();
    _seasonController.dispose();
    _brandController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = _savedLocalId != null;
    final isEditing = widget.itemId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? 'Edit wardrobe item'
              : isSaved
              ? 'Saved item'
              : 'Add wardrobe item',
        ),
      ),
      body: _isLoadingExisting
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading wardrobe item',
              ),
            )
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _photoSection(),
            const SizedBox(height: 24),
            _textField(
              controller: _titleController,
              label: 'Title',
              requiredField: true,
              maxLength: 200,
            ),
            _textField(
              controller: _categoryController,
              label: 'Category',
              requiredField: true,
              maxLength: 80,
            ),
            _textField(
              controller: _subcategoryController,
              label: 'Subcategory',
              maxLength: 80,
            ),
            _textField(
              controller: _primaryColorController,
              label: 'Primary color',
              maxLength: 80,
            ),
            _textField(
              controller: _secondaryColorController,
              label: 'Secondary color',
              maxLength: 80,
            ),
            _textField(
              controller: _styleTagsController,
              label: 'Style tags',
              hint: 'Separate tags with commas',
              maxLength: 300,
            ),
            _textField(
              controller: _occasionController,
              label: 'Occasion',
              maxLength: 80,
            ),
            _textField(
              controller: _seasonController,
              label: 'Season',
              maxLength: 80,
            ),
            _textField(
              controller: _brandController,
              label: 'Brand (optional)',
              maxLength: 100,
            ),
            _textField(
              controller: _notesController,
              label: 'Notes',
              maxLength: 1000,
              maxLines: 3,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Favorite'),
              value: _isFavorite,
              onChanged: isSaved && !isEditing
                  ? null
                  : (value) => setState(() => _isFavorite = value),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                _saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSaving || _isSyncing ? null : _saveOrRetry,
              icon: _isSaving || _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isSaved ? Icons.cloud_upload_outlined : Icons.save),
              label: Text(
                _isSaving
                    ? 'Saving on this device…'
                    : _isSyncing
                    ? 'Syncing…'
                    : isEditing
                    ? 'Save changes'
                    : isSaved
                    ? 'Retry cloud upload'
                    : 'Save item',
              ),
            ),
            if (isSaved || isEditing)
              TextButton(
                onPressed: _isSaving || _isSyncing
                    ? null
                    : context.pop,
                child: Text(isEditing ? 'Cancel' : 'Done'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _photoSection() {
    final photo = _photoBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 0.9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: photo != null
                ? Image.memory(photo, fit: BoxFit.cover)
                : _existingItem?.localImagePath != null
                ? WardrobePhoto(path: _existingItem!.localImagePath)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
                    child: const Center(
                      child: Icon(Icons.add_a_photo_outlined, size: 48),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isPreparingPhoto ||
                        (_savedLocalId != null && widget.itemId == null)
                    ? null
                    : () => _choosePhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isPreparingPhoto ||
                        (_savedLocalId != null && widget.itemId == null)
                    ? null
                    : () => _choosePhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        if (_isPreparingPhoto) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          const Text('Preparing a private, compressed copy…'),
        ],
        if (_photoError != null) ...[
          const SizedBox(height: 8),
          Text(
            _photoError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Photos are resized and compressed before being saved on this device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool requiredField = false,
    int maxLength = 200,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('wardrobe-field-$label'),
        controller: controller,
        enabled: _savedLocalId == null || widget.itemId != null,
        maxLength: maxLength,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: requiredField
            ? (value) => value == null || value.trim().isEmpty
                  ? 'Enter a $label.'
                  : null
            : null,
      ),
    );
  }

  Future<void> _choosePhoto(ImageSource source) async {
    setState(() {
      _isPreparingPhoto = true;
      _photoError = null;
    });
    try {
      final selected = await ref.read(wardrobeImagePickerProvider).pick(source);
      if (selected == null || !mounted) return;
      final compressed = await ref
          .read(wardrobeImageProcessorProvider)
          .compress(
        selected,
      );
      if (!mounted) return;
      setState(() => _photoBytes = compressed);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _photoError = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isPreparingPhoto = false);
    }
  }

  Future<void> _saveOrRetry() async {
    if (widget.itemId != null) {
      await _saveEdit();
      return;
    }
    if (_savedLocalId != null) {
      await _retryCloudUpload();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final photoBytes = _photoBytes;
    if (photoBytes == null) {
      setState(() => _photoError = 'Choose a photo before saving this item.');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final localId = _newUuid();
      final item = GuestWardrobeItem(
        localId: localId,
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        subcategory: _optionalValue(_subcategoryController),
        createdAt: DateTime.now(),
        primaryColor: _optionalValue(_primaryColorController),
        secondaryColor: _optionalValue(_secondaryColorController),
        styleTags: _commaSeparatedValues(_styleTagsController.text),
        occasion: _optionalValue(_occasionController),
        season: _optionalValue(_seasonController),
        brand: _optionalValue(_brandController),
        notes: _optionalValue(_notesController),
        isFavorite: _isFavorite,
        needsCloudSync: true,
      );
      final savedItem = await ref
          .read(wardrobeRepositoryProvider)
          .createItem(item, photoBytes);
      if (!mounted) return;
      _savedLocalId = savedItem.localId;
      ref.invalidate(wardrobeItemsProvider);

      final userId = ref.read(authGatewayProvider)?.currentSession?.userId;
      if (userId == null) {
        setState(() {
          _isSaving = false;
          _saveError =
              'Saved on this device. Sign in to upload it to your account.';
        });
        return;
      }
      await _syncSavedItem(userId);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = _messageFor(error);
      });
    }
  }

  Future<void> _saveEdit() async {
    if (!_formKey.currentState!.validate()) return;
    final existingItem = _existingItem;
    if (existingItem == null) {
      setState(() => _saveError = 'This wardrobe item could not be loaded.');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final item = GuestWardrobeItem(
        localId: existingItem.localId,
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        subcategory: _optionalValue(_subcategoryController),
        createdAt: existingItem.createdAt,
        primaryColor: _optionalValue(_primaryColorController),
        secondaryColor: _optionalValue(_secondaryColorController),
        styleTags: _commaSeparatedValues(_styleTagsController.text),
        occasion: _optionalValue(_occasionController),
        season: _optionalValue(_seasonController),
        brand: _optionalValue(_brandController),
        size: existingItem.size,
        notes: _optionalValue(_notesController),
        localImagePath: existingItem.localImagePath,
        imageContentType: existingItem.imageContentType,
        isFavorite: _isFavorite,
        isArchived: existingItem.isArchived,
        needsCloudSync: true,
        hasCloudCopy: existingItem.hasCloudCopy,
      );
      final savedItem = await ref
          .read(wardrobeRepositoryProvider)
          .updateItem(item, replacementPhotoBytes: _photoBytes);
      if (!mounted) return;
      setState(() {
        _existingItem = savedItem;
        _photoBytes = null;
        _isSaving = false;
      });
      ref.invalidate(wardrobeItemsProvider);

      final userId = ref.read(authGatewayProvider)?.currentSession?.userId;
      if (userId == null) {
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Changes saved on this device.')),
        );
        return;
      }
      await _syncSavedItem(userId);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = _messageFor(error);
      });
    }
  }

  Future<void> _retryCloudUpload() async {
    final userId = ref.read(authGatewayProvider)?.currentSession?.userId;
    if (userId == null) {
      setState(() => _saveError = 'Sign in before retrying the cloud upload.');
      return;
    }
    await _syncSavedItem(userId);
  }

  Future<void> _syncSavedItem(String userId) async {
    final localId = _savedLocalId ?? _existingItem?.localId;
    if (localId == null) return;
    setState(() {
      _isSaving = false;
      _isSyncing = true;
      _saveError = null;
    });
    try {
      await ref
          .read(wardrobeSyncServiceProvider)
          .syncItem(userId, localId)
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      ref.invalidate(wardrobeItemsProvider);
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Item saved and synced to your account.')),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ref.invalidate(wardrobeItemsProvider);
      setState(() {
        _isSyncing = false;
        _saveError =
            'Saved locally; cloud upload is pending. ${_messageFor(error)}';
      });
    }
  }
}

String? _optionalValue(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}

List<String> _commaSeparatedValues(String value) {
  return List<String>.unmodifiable(
    value
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet(),
  );
}

String _messageFor(Object error) {
  return error is AppError
      ? error.message
      : 'The item could not be saved. Your local data is unchanged.';
}

String _newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
