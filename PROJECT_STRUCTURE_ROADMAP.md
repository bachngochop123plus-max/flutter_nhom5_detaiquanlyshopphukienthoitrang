# FASHION ACCESSORIES SHOP - CẬP NHẬT CẤU TRÚC & LUỒNG THỰC HIỆN

Tài liệu này mô tả đúng trạng thái code hiện tại của dự án, gồm:
- Toàn bộ cấu trúc chức năng đang có.
- Luồng thực thi chính từ khi mở app tới các nghiệp vụ.
- Luồng dữ liệu Supabase/API/SQLite.
- Hạng mục chưa làm để tiếp tục phát triển.

Ngày cập nhật: April 15, 2026
Framework: Flutter
Kiến trúc thực tế: Feature-first + Service/Repository + Cubit

---

## 1) TOÀN BỘ CẤU TRÚC CHỨC NĂNG HIỆN CÓ

```text
detai_shopbanphukienthoitrang/
│
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/
│   │   ├── config/
│   │   │   ├── api_config.dart
│   │   │   └── supabase_config.dart
│   │   ├── constants/
│   │   │   └── app_assets.dart
│   │   ├── data/
│   │   │   ├── catalog_repository.dart
│   │   │   └── database_helper.dart
│   │   ├── di/
│   │   │   └── injection_container.dart
│   │   ├── errors/
│   │   │   └── failure.dart
│   │   ├── models/
│   │   │   └── product.dart
│   │   ├── router/
│   │   │   ├── app_router.dart
│   │   │   └── go_router_refresh_stream.dart
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   ├── device_service.dart
│   │   │   ├── supabase_auth_repository.dart
│   │   │   └── supabase_storage_service.dart
│   │   ├── theme/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_text_styles.dart
│   │   │   └── app_theme.dart
│   │   └── widgets/
│   │       ├── base_screen.dart
│   │       ├── keyboard_dismiss_on_tap.dart
│   │       └── loading_overlay.dart
│   │
│   └── features/
│       ├── admin/
│       │   └── presentation/pages/
│       │       ├── admin_page.dart
│       │       ├── admin_inventory_page.dart
│       │       └── admin_edit_product_page.dart
│       ├── auth/
│       │   └── presentation/cubit/
│       │       └── auth_cubit.dart
│       ├── cart/
│       │   └── presentation/
│       │       ├── cubit/cart_cubit.dart
│       │       └── pages/cart_page.dart
│       ├── favorites/
│       │   └── presentation/pages/favorites_page.dart
│       ├── home/
│       │   └── presentation/pages/home_page.dart
│       ├── login/
│       │   └── presentation/pages/
│       │       ├── login_page.dart
│       │       └── register_page.dart
│       ├── product_detail/
│       │   └── presentation/pages/product_detail_page.dart
│       ├── profile/
│       │   └── presentation/pages/profile_page.dart
│       ├── shell/
│       │   └── main_shell.dart
│       └── store_locator/
│           └── presentation/pages/store_locator_page.dart
│
├── assets/
│   ├── images/
│   └── icons/
│
└── test/
		└── (chưa có test files)
```

---

## 2) BẢN ĐỒ CHỨC NĂNG THEO MODULE

### 2.1 App bootstrap
- `main.dart`
	- `WidgetsFlutterBinding.ensureInitialized()`
	- Khởi tạo Supabase nếu cấu hình hợp lệ.
	- Gọi `bootstrapDependencies()`.
	- `runApp(FashionShopApp)`.
- `app.dart`
	- Cấp `AuthCubit` + `CartCubit` qua `MultiBlocProvider`.
	- Dùng `MaterialApp.router` với `buildAppRouter(...)`.

### 2.2 Core DI và service
- `injection_container.dart`
	- Đăng ký singleton: `ApiService`, `DatabaseHelper`, `SupabaseAuthRepository`, `SupabaseStorageService`, `CatalogRepository`, `AuthCubit`, `CartCubit`.
	- Khởi tạo DB local.
	- Warm-up sản phẩm vào memory.

### 2.3 Routing và phân quyền
- `app_router.dart`
	- Public: `/home`, `/cart`, `/favorites`, `/stores`, `/profile`, `/login`, `/register`.
	- Admin: `/admin`, `/admin/inventory`, `/admin/inventory/new`, `/admin/inventory/edit`.
	- Guard:
		- Nếu vào route admin mà không phải admin -> redirect `/home`.
		- Nếu đã đăng nhập mà vào `/login` -> redirect `/home`.

### 2.4 Auth
- `auth_cubit.dart`
	- Trạng thái vai trò: `guest | user | admin`.
	- `login(...)`, `logout()`.
- `supabase_auth_repository.dart`
	- `signIn`: ưu tiên Supabase; fallback local SQLite nếu chưa cấu hình Supabase.
	- `signUp`: Supabase auth sign up hoặc local create user.
	- `signOut`: đăng xuất Supabase.

### 2.5 Catalog và nguồn dữ liệu
- `catalog_repository.dart`
	- Chuyển đổi nguồn dữ liệu theo cấu hình:
		- Có Supabase: đọc/ghi từ Supabase tables.
		- Không Supabase: dùng SQLite local + API fallback.
	- CRUD sản phẩm:
		- `createProduct`
		- `updateProduct`
		- `deleteProduct`
	- Đồng bộ memory list `_memoryProducts` cho UI.
	- Chuyển path ảnh thành public URL.
	- Khi xóa sản phẩm trên Supabase: xóa file trong Storage bucket trước, rồi xóa bản ghi DB liên quan.

### 2.6 Storage ảnh
- `supabase_storage_service.dart`
	- Chọn ảnh từ gallery.
	- Upload binary lên bucket `Img_products`, folder `Img_Product/{productId}/...`.
	- Trả public URL sau upload.
	- Bắt lỗi RLS 403 và trả message hướng dẫn policy.

### 2.7 Feature UI hiện có
- `home_page.dart`: catalog, filter danh mục, entry login/admin/profile theo role.
- `product_detail_page.dart`: xem chi tiết, chọn biến thể, add cart, toggle favorites.
- `cart_page.dart`: tăng/giảm/xóa item, clear cart.
- `favorites_page.dart`: đọc favorites từ local DB, kéo để xóa.
- `profile_page.dart`: chụp avatar (camera), đọc contacts, mở SMS mời bạn.
- `store_locator_page.dart`: Google Map + vị trí hiện tại + ước lượng khoảng cách/thời gian.
- `admin_page.dart`: dashboard điều hướng admin.
- `admin_inventory_page.dart`: danh sách sản phẩm, edit/delete/create.
- `admin_edit_product_page.dart`: form tạo/sửa/xóa sản phẩm, upload ảnh sản phẩm.

---

## 3) LUỒNG THỰC HIỆN CHÍNH (END-TO-END)

### Luồng A: Mở app
1. App chạy `main()`.
2. Nạp config Supabase, nếu hợp lệ thì `Supabase.initialize(...)`.
3. `bootstrapDependencies()` đăng ký DI, init SQLite, warm-up catalog.
4. Router khởi động ở `/home`.

### Luồng B: Đăng ký / đăng nhập / phân quyền
1. User vào `/register` tạo tài khoản.
2. User vào `/login` đăng nhập thường hoặc đăng nhập yêu cầu admin.
3. `SupabaseAuthRepository.signIn()` trả `displayName + role`.
4. `AuthCubit.login(...)` cập nhật state.
5. Router guard áp dụng role:
	 - user thường không vào được `/admin/*`.
	 - admin vào được toàn bộ route admin.

### Luồng C: Duyệt sản phẩm và mua
1. Home hiển thị products từ memory repository.
2. Chọn sản phẩm -> route `/home/product`.
3. Product detail cho chọn color/size.
4. Nhấn thêm giỏ -> `CartCubit.addProduct(...)`.
5. Vào cart để tăng/giảm/xóa hoặc clear.

### Luồng D: Yêu thích sản phẩm
1. Tại product detail bấm favorite.
2. DB local cập nhật bảng favorites.
3. Mở tab Favorites để xem danh sách.
4. Vuốt item để xóa favorite.

### Luồng E: Admin quản lý sản phẩm
1. Admin vào `/admin` -> mở inventory.
2. Tạo mới:
	 - nhập form -> `CatalogRepository.createProduct(...)`.
	 - chọn ảnh -> upload Supabase Storage.
	 - update lại sản phẩm với `imageUrl/gallery`.
3. Chỉnh sửa:
	 - cập nhật thông tin + ảnh -> `updateProduct(...)`.
4. Xóa:
	 - `deleteProduct(...)`.
	 - nếu dùng Supabase: lấy ảnh thumbnail/gallery -> xóa object Storage -> xóa rows `product_images`, `product_variants`, `products`.

### Luồng F: Profile và thiết bị
1. User chụp avatar bằng camera (`image_picker`).
2. User tải danh bạ (`flutter_contacts`).
3. Bấm SMS để mở app nhắn tin (`url_launcher`).

### Luồng G: Store locator
1. Xin quyền location.
2. Lấy vị trí hiện tại bằng `geolocator`.
3. Vẽ map + marker + polyline tới chi nhánh.
4. Tính khoảng cách và thời gian ước lượng.

---

## 4) LUỒNG DỮ LIỆU & TƯƠNG TÁC HỆ THỐNG

### 4.1 Data source strategy
- Supabase configured:
	- Auth: Supabase Auth
	- Catalog: Supabase tables
	- Image: Supabase Storage
- Supabase không configured:
	- Auth: local SQLite users
	- Catalog: local SQLite + API fallback (DummyJSON)
	- Image upload: bỏ qua (trả `null`)

### 4.2 Bảng dữ liệu local chính (SQLite)
Trong `database_helper.dart` đã khai báo schema chuẩn hóa gồm:
- `roles`
- `users`
- `categories`
- `products`
- `product_variants`
- `product_images`
- `product_tags`
- `favorites`
- `orders`
- `order_items`
- `reviews`

### 4.3 Supabase entities đang dùng trong code
- Auth: `auth.users` qua Supabase SDK
- App tables:
	- `products`
	- `product_images`
	- `product_variants`
	- `categories`
	- `profiles`
	- `roles`
- Storage:
	- bucket: `Img_products`
	- folder convention: `Img_Product/{productId}/...`

---

## 5) ROUTES ĐANG HOẠT ĐỘNG

```text
/login
/register
/admin
/admin/inventory
/admin/inventory/new
/admin/inventory/edit

/home
/home/product
/cart
/favorites
/stores
/profile
```

Ghi chú:
- `/home/product` nhận product qua `state.extra`.
- `/admin/inventory/edit` nhận product qua `state.extra`.

---

## 6) DANH MỤC TÍNH NĂNG: HOÀN THÀNH / CHƯA HOÀN THÀNH

### 6.1 Đã có và chạy được
- Đăng nhập + đăng ký.
- Role user/admin và route guard admin.
- Catalog listing + detail + filter.
- Cart state management.
- Favorites local.
- Admin CRUD sản phẩm.
- Upload ảnh sản phẩm lên Supabase Storage.
- Xóa ảnh Storage khi xóa sản phẩm.
- Profile: camera + contacts + SMS intent.
- Store locator map + location.

### 6.2 Chưa hoàn thiện / chưa triển khai đủ
- Unit/widget/integration tests (thư mục test đang trống).
- Checkout/payment thực tế.
- Đơn hàng end-to-end từ cart -> order.
- Review/rating đầy đủ UI + moderation.
- Search nâng cao + sort/filter chuyên sâu.
- Notification push + analytics.
- CI/CD và release pipeline.

---

## 7) RỦI RO VẬN HÀNH & LƯU Ý TRIỂN KHAI

1. Supabase Storage cần policy đúng cho upload/update/delete object.
2. Quyền admin phụ thuộc role mapping trong Supabase (`get_my_role`, `profiles`, `roles`).
3. Khi dùng local fallback, một số hành vi (nhất là ảnh cloud) khác với môi trường Supabase.
4. Cần bổ sung test để tránh regression cho luồng admin CRUD và auth role guard.

---

## 8) ROADMAP NGẮN HẠN ĐỀ XUẤT (ƯU TIÊN)

### Ưu tiên 1: Độ ổn định
1. Viết test cho `CatalogRepository` (create/update/delete, xóa ảnh storage path parser).
2. Viết test router guard (guest/user/admin).
3. Thêm xử lý lỗi hiển thị rõ hơn cho upload/delete ảnh.

### Ưu tiên 2: Nghiệp vụ commerce
1. Checkout flow.
2. Tạo order từ cart.
3. Order history + detail page.

### Ưu tiên 3: Chất lượng sản phẩm
1. CI lint + analyze + test.
2. Logging/analytics sự kiện chính.
3. Tối ưu UX mobile cho admin inventory.

---

## 9) CHECKLIST CẬP NHẬT TÀI LIỆU (CHO MỖI LẦN THAY ĐỔI)

Khi thêm/chỉnh sửa feature, cập nhật lại các mục sau trong tài liệu này:
1. Cây thư mục ở Mục 1.
2. Bản đồ chức năng ở Mục 2.
3. Luồng thực hiện liên quan ở Mục 3.
4. Routes ở Mục 5.
5. Trạng thái hoàn thành ở Mục 6.

Tình trạng hiện tại: Tài liệu đã đồng bộ với source code tại ngày 15/04/2026.
