import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/data/catalog_repository.dart';
import '../../../../core/models/product.dart';
import '../../../../core/services/supabase_storage_service.dart';
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
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final CatalogRepository _catalogRepository;
  late final SupabaseStorageService _storageService;

  bool _saving = false;
  XFile? _pickedImage;
  String? _pickedImageName;

  Product get _draftProduct {
    if (widget.product != null) {
      return widget.product!;
    }

    return const Product(
      id: 'new',
      name: '',
      description: '',
      imageUrl: '',
      category: 'Phu kien',
      price: 0,
      isDiscounted: false,
      rating: 0,
      gallery: [],
      availableColors: ['Default'],
      availableSizes: ['Free size'],
    );
  }

  @override
  void initState() {
    super.initState();
    _catalogRepository = GetIt.instance<CatalogRepository>();
    _storageService = GetIt.instance<SupabaseStorageService>();
    _nameController = TextEditingController(text: _draftProduct.name);
    _descriptionController = TextEditingController(
      text: _draftProduct.description,
    );
    _categoryController = TextEditingController(text: _draftProduct.category);
    _priceController = TextEditingController(
      text: _draftProduct.price.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _storageService.pickSingleImage();
    if (!mounted || picked == null) return;

    setState(() {
      _pickedImage = picked;
      _pickedImageName = picked.name;
    });
  }

  void _closeEditor([bool? result]) {
    if (context.canPop()) {
      context.pop(result);
      return;
    }

    context.go('/admin/inventory');
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim());

    if (name.isEmpty || category.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên, danh mục và giá hợp lệ.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final draft = _draftProduct.copyWith(
        name: name,
        description: description,
        category: category,
        price: price,
      );

      Object? uploadWarning;

      if (widget.isCreating || widget.product == null) {
        final created = await _catalogRepository.createProduct(draft);
        if (_pickedImage != null) {
          try {
            final uploadedUrl = await _storageService.uploadProductImage(
              productId: created.id,
              file: _pickedImage!,
            );
            if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
              await _catalogRepository.updateProduct(
                created.copyWith(imageUrl: uploadedUrl, gallery: [uploadedUrl]),
              );
            }
          } catch (error) {
            uploadWarning = error;
          }
        }
      } else {
        var imageUrl = _draftProduct.imageUrl;
        var gallery = _draftProduct.gallery;

        if (_pickedImage != null) {
          try {
            final uploadedUrl = await _storageService.uploadProductImage(
              productId: _draftProduct.id,
              file: _pickedImage!,
            );
            if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
              imageUrl = uploadedUrl;
              gallery = [
                uploadedUrl,
                ..._draftProduct.gallery.where((item) => item != uploadedUrl),
              ];
            }
          } catch (error) {
            uploadWarning = error;
          }
        }

        await _catalogRepository.updateProduct(
          draft.copyWith(imageUrl: imageUrl, gallery: gallery),
        );
      }

      if (!mounted) return;
      final uploadedErrorMessage = uploadWarning?.toString();
      if (uploadedErrorMessage != null) {
        final message = uploadedErrorMessage.startsWith('Exception: ')
            ? uploadedErrorMessage.substring(11)
            : uploadedErrorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Da luu san pham, nhung upload anh that bai: $message',
            ),
          ),
        );
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thông tin sản phẩm.')),
        );
      }
      _closeEditor(true);
    } catch (error) {
      if (!mounted) return;
      final rawMessage = error.toString();
      final message = rawMessage.startsWith('Exception: ')
          ? rawMessage.substring(11)
          : rawMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Khong the luu san pham: $message')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteProduct() async {
    final product = widget.product;
    if (product == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoa san pham'),
        content: Text('Ban chac chan muon xoa "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _catalogRepository.deleteProduct(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Da xoa san pham.')));
      _closeEditor(true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: widget.isCreating ? 'Thêm sản phẩm' : 'Chỉnh sửa sản phẩm',
      isLoading: _saving,
      leading: IconButton(
        tooltip: 'Quay lai',
        onPressed: () => _closeEditor(false),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      automaticallyImplyLeading: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isCreating
                        ? 'Tạo sản phẩm mới'
                        : 'Chỉnh sửa thông tin sản phẩm',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên sản phẩm',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Danh mục',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Giá',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _pickedImageName == null
                          ? 'Chọn ảnh'
                          : 'Đã chọn: $_pickedImageName',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload vào bucket Img_products / folder Img_Product',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  if (!widget.isCreating && widget.product != null) ...[
                    FilledButton.tonalIcon(
                      onPressed: _saving ? null : _deleteProduct,
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Xoa san pham'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _closeEditor(false),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(
                            widget.isCreating ? 'Tạo sản phẩm' : 'Lưu thay đổi',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
