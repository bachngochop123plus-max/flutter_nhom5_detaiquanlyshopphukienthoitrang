import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';
import '../../../../core/services/supabase_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/base_screen.dart';

class AdminEditProductPage extends StatefulWidget {
  const AdminEditProductPage({
    super.key,
    this.product,
    this.isCreating = false,
  });

  final Product? product;
  final bool isCreating;

  @override
  State<AdminEditProductPage> createState() => _AdminEditProductPageState();
}

class _AdminEditProductPageState extends State<AdminEditProductPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final CatalogRepository _catalogRepository;
  late final SupabaseStorageService _storageService;

  // Category
  List<String> _categoryOptions = [];
  String? _selectedCategory;

  // Main image
  XFile? _mainImageFile;
  String? _existingMainImageUrl;

  // Gallery
  List<String> _existingGalleryUrls = [];
  List<XFile> _newGalleryFiles = [];

  bool _saving = false;
  bool _initialLoading = true;

  Product get _draft => widget.product ??
      const Product(
        id: 'new',
        name: '',
        description: '',
        imageUrl: '',
        category: '',
        price: 0,
        isDiscounted: false,
        rating: 0,
        gallery: [],
        availableColors: [],
        availableSizes: [],
      );

  @override
  void initState() {
    super.initState();
    _catalogRepository = GetIt.instance<CatalogRepository>();
    _storageService = GetIt.instance<SupabaseStorageService>();
    _nameController = TextEditingController(text: _draft.name);
    _descriptionController = TextEditingController(text: _draft.description);
    _priceController = TextEditingController(
      text: _draft.price == 0 ? '' : _draft.price.toStringAsFixed(0),
    );
    _stockController = TextEditingController(text: '0');
    _existingMainImageUrl =
        _draft.imageUrl.isNotEmpty ? _draft.imageUrl : null;
    _initAsync();
  }

  Future<void> _initAsync() async {
    await Future.wait([
      _loadCategories(),
      if (!widget.isCreating) _loadExistingGallery(),
    ]);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _loadCategories() async {
    await _catalogRepository.loadCategories();
    if (!mounted) return;
    final cats = _catalogRepository.getCategories();
    final names = cats.map((c) => c.name).toList();
    final current = _draft.category;
    if (current.isNotEmpty && !names.contains(current)) {
      names.insert(0, current);
    }
    setState(() {
      _categoryOptions = names;
      _selectedCategory = names.contains(current)
          ? current
          : (names.isNotEmpty ? names.first : null);
    });
  }

  Future<void> _loadExistingGallery() async {
    if (widget.product == null) return;
    try {
      final urls =
          await _catalogRepository.getGalleryForProduct(widget.product!.id);
      if (!mounted) return;
      final main = _existingMainImageUrl ?? '';
      setState(() {
        _existingGalleryUrls = urls.where((u) => u != main).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickMainImage() async {
    final file = await _storageService.pickSingleImage();
    if (file != null && mounted) setState(() => _mainImageFile = file);
  }

  Future<void> _pickGalleryImages() async {
    final files = await _storageService.pickMultipleImages();
    if (files.isNotEmpty && mounted) {
      setState(() => _newGalleryFiles.addAll(files));
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final category = _selectedCategory ?? '';
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim());

    if (name.isEmpty || category.isEmpty || price == null || price < 0) {
      _showSnack('Vui lòng nhập tên, danh mục và giá hợp lệ.', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      String mainImageUrl = _existingMainImageUrl ?? '';
      List<String> gallery = List.from(_existingGalleryUrls);

      // Upload main image
      if (_mainImageFile != null) {
        final uploaded = await _storageService.uploadProductImage(
          productId: widget.isCreating ? 'new_tmp' : _draft.id,
          file: _mainImageFile!,
        );
        if (uploaded != null && uploaded.isNotEmpty) mainImageUrl = uploaded;
      }

      // Upload gallery images
      for (final file in _newGalleryFiles) {
        final uploaded = await _storageService.uploadProductImage(
          productId: widget.isCreating ? 'new_tmp' : _draft.id,
          file: file,
        );
        if (uploaded != null && uploaded.isNotEmpty) gallery.add(uploaded);
      }

      final finalGallery = [
        if (mainImageUrl.isNotEmpty) mainImageUrl,
        ...gallery.where((u) => u != mainImageUrl),
      ];

      final productDraft = _draft.copyWith(
        name: name,
        description: description,
        category: category,
        price: price,
        imageUrl: mainImageUrl,
        gallery: finalGallery,
      );

      if (widget.isCreating) {
        final defaultStock =
            int.tryParse(_stockController.text.trim()) ?? 0;
        await _catalogRepository.createProduct(
          productDraft,
          defaultStock: defaultStock,
        );
      } else {
        await _catalogRepository.updateProduct(productDraft);
      }

      if (!mounted) return;
      _showSnack('Đã lưu thông tin sản phẩm thành công.');
      _closeEditor(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      _showSnack('Lỗi: $msg', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteProduct() async {
    final product = widget.product;
    if (product == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn chắc chắn muốn xóa "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _catalogRepository.deleteProduct(product.id);
      if (!mounted) return;
      _showSnack('Đã xóa sản phẩm.');
      _closeEditor(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _closeEditor([bool? result]) {
    if (context.canPop()) context.pop(result);
    else context.go('/admin/inventory');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: widget.isCreating ? 'Thêm sản phẩm mới' : 'Chỉnh sửa sản phẩm',
      isLoading: _saving,
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: () => _closeEditor(false),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      automaticallyImplyLeading: false,
      body: _initialLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.luxuryGold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Thông tin cơ bản
                      const _SectionHeader(label: 'Thông tin sản phẩm'),
                      const SizedBox(height: 12),
                      _buildField(
                        _nameController,
                        'Tên sản phẩm *',
                        'Nhập tên sản phẩm...',
                        Icons.label_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildCategoryDropdown(),
                      const SizedBox(height: 12),
                      _buildField(
                        _descriptionController,
                        'Mô tả',
                        'Nhập mô tả chi tiết...',
                        Icons.notes_rounded,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        _priceController,
                        'Giá bán (VNĐ) *',
                        'Ví dụ: 350000',
                        Icons.payments_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),

                      // ── Số lượng (chỉ khi tạo mới)
                      if (widget.isCreating) ...[
                        const SizedBox(height: 12),
                        _buildStockField(),
                      ],

                      const SizedBox(height: 24),

                      // ── Ảnh chính
                      const _SectionHeader(label: 'Ảnh chính'),
                      const SizedBox(height: 12),
                      _buildMainImagePicker(),

                      const SizedBox(height: 24),

                      // ── Ảnh gallery
                      const _SectionHeader(label: 'Ảnh bổ sung (gallery)'),
                      const SizedBox(height: 6),
                      Text(
                        'Thêm nhiều ảnh liên quan đến sản phẩm.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.softGray),
                      ),
                      const SizedBox(height: 10),
                      _buildGallerySection(),

                      const SizedBox(height: 28),

                      // ── Xóa (chỉ khi sửa)
                      if (!widget.isCreating && widget.product != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _deleteProduct,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Xóa sản phẩm này'),
                          ),
                        ),

                      // ── Save / Cancel
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _saving ? null : () => _closeEditor(false),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Hủy'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.luxuryGold,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                widget.isCreating
                                    ? 'Tạo sản phẩm'
                                    : 'Lưu thay đổi',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ── Stock field (create only)
  Widget _buildStockField() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 16, color: AppColors.softGray),
            const SizedBox(width: 6),
            Text('Số lượng tồn kho',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600, color: AppColors.softGray)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StockBtn(
              icon: Icons.remove_rounded,
              onTap: () {
                final cur = int.tryParse(_stockController.text) ?? 0;
                if (cur > 0) _stockController.text = '${cur - 1}';
              },
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _stockController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: AppColors.luxuryGold
                            .withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppColors.luxuryGold, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StockBtn(
              icon: Icons.add_rounded,
              onTap: () {
                final cur = int.tryParse(_stockController.text) ?? 0;
                _stockController.text = '${cur + 1}';
              },
            ),
            const SizedBox(width: 12),
            Text('sản phẩm',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.softGray)),
          ],
        ),
      ],
    );
  }

  // ── Main image picker
  Widget _buildMainImagePicker() {
    final hasNew = _mainImageFile != null;
    final hasExisting =
        _existingMainImageUrl != null && _existingMainImageUrl!.isNotEmpty;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: _saving ? null : _pickMainImage,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (hasNew || hasExisting)
                ? AppColors.luxuryGold
                : AppColors.luxuryGold.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasNew)
                Container(
                  color: AppColors.luxuryGold.withValues(alpha: 0.08),
                  child: const Center(
                    child: Icon(Icons.check_circle_rounded,
                        size: 52, color: AppColors.luxuryGold),
                  ),
                )
              else if (hasExisting)
                CachedNetworkImage(
                  imageUrl: _existingMainImageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _imgPlaceholder(),
                )
              else
                _imgPlaceholder(),
              if (hasExisting && !hasNew)
                Positioned.fill(
                  child: Container(
                      color: Colors.black.withValues(alpha: 0.35)),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 12),
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          hasNew
                              ? 'Đã chọn: ${_mainImageFile!.name}'
                              : hasExisting
                                  ? 'Bấm để thay ảnh chính'
                                  : 'Bấm để chọn ảnh chính',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: AppColors.luxuryGold.withValues(alpha: 0.06),
        child: const Center(
          child: Icon(Icons.add_photo_alternate_outlined,
              color: AppColors.luxuryGold, size: 48),
        ),
      );

  // ── Gallery section
  Widget _buildGallerySection() {
    final theme = Theme.of(context);
    final total = _existingGalleryUrls.length + _newGalleryFiles.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.luxuryGold.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total > 0) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: total,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemBuilder: (_, index) {
                if (index < _existingGalleryUrls.length) {
                  final url = _existingGalleryUrls[index];
                  return _GalleryThumb(
                    onRemove: () => setState(
                        () => _existingGalleryUrls.remove(url)),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.softGray),
                    ),
                  );
                }
                final i = index - _existingGalleryUrls.length;
                final file = _newGalleryFiles[i];
                return _GalleryThumb(
                  isNew: true,
                  onRemove: () =>
                      setState(() => _newGalleryFiles.removeAt(i)),
                  child: Container(
                    color: AppColors.luxuryGold.withValues(alpha: 0.1),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_outlined,
                              color: AppColors.luxuryGold, size: 26),
                          const SizedBox(height: 4),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              file.name,
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.luxuryGold),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickGalleryImages,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.luxuryGold,
              side: BorderSide(
                  color: AppColors.luxuryGold.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon:
                const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(
              total == 0
                  ? 'Thêm ảnh bổ sung'
                  : '+ Thêm ảnh ($total ảnh hiện tại)',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form helpers
  Widget _buildField(
    TextEditingController c,
    String label,
    String hint,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.luxuryGold.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.luxuryGold, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    if (_categoryOptions.isEmpty) {
      return const LinearProgressIndicator(color: AppColors.luxuryGold);
    }
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: InputDecoration(
        labelText: 'Danh mục *',
        prefixIcon: const Icon(Icons.category_outlined, size: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.luxuryGold.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.luxuryGold, width: 1.5),
        ),
      ),
      items: _categoryOptions
          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
          .toList(),
      onChanged: (v) => setState(() => _selectedCategory = v),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.luxuryGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({
    required this.child,
    required this.onRemove,
    this.isNew = false,
  });

  final Widget child;
  final VoidCallback onRemove;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(10), child: child),
        if (isNew)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.luxuryGold,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Mới',
                  style: TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _StockBtn extends StatelessWidget {
  const _StockBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.luxuryGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.luxuryGold),
      ),
    );
  }
}
