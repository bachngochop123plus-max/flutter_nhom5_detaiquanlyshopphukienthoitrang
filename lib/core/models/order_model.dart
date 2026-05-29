class OrderItemModel {
  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.variantId,
    required this.quantity,
    required this.priceAtPurchase,
    this.productName,
    this.color,
    this.size,
    this.thumbnail,
  });

  final int id;
  final int orderId;
  final int variantId;
  final int quantity;
  final double priceAtPurchase;
  final String? productName;
  final String? color;
  final String? size;
  final String? thumbnail;

  double get lineTotal => priceAtPurchase * quantity;

  factory OrderItemModel.fromMap(Map<String, Object?> map) {
    return OrderItemModel(
      id: map['id'] as int,
      orderId: map['order_id'] as int,
      variantId: map['variant_id'] as int,
      quantity: map['quantity'] as int,
      priceAtPurchase: (map['price_at_purchase'] as num).toDouble(),
      productName: map['product_name'] as String?,
      color: map['color'] as String?,
      size: map['size'] as String?,
      thumbnail: map['thumbnail'] as String?,
    );
  }
}

class OrderModel {
  const OrderModel({
    required this.id,
    required this.userId,
    required this.orderDate,
    required this.totalAmount,
    required this.status,
    required this.paymentStatus,
    required this.shippingAddress,
    this.paymentMethod,
    this.customerName,
    this.customerEmail,
    this.items = const [],
  });

  final int id;
  final int userId;
  final DateTime orderDate;
  final double totalAmount;
  final String status;
  final String paymentStatus;
  final String shippingAddress;
  final String? paymentMethod;
  final String? customerName;
  final String? customerEmail;
  final List<OrderItemModel> items;

  factory OrderModel.fromMap(Map<String, Object?> map) {
    return OrderModel(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      orderDate: DateTime.parse(map['order_date'] as String),
      totalAmount: (map['total_amount'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending',
      paymentStatus: map['payment_status'] as String? ?? 'unpaid',
      shippingAddress: map['shipping_address'] as String? ?? '',
      paymentMethod: map['payment_method'] as String?,
      customerName: map['customer_name'] as String?,
      customerEmail: map['customer_email'] as String?,
    );
  }

  OrderModel copyWith({
    List<OrderItemModel>? items,
    String? status,
    String? paymentStatus,
  }) {
    return OrderModel(
      id: id,
      userId: userId,
      orderDate: orderDate,
      totalAmount: totalAmount,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      shippingAddress: shippingAddress,
      paymentMethod: paymentMethod,
      customerName: customerName,
      customerEmail: customerEmail,
      items: items ?? this.items,
    );
  }

  /// Human-readable status label (Vietnamese)
  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Chờ xử lý';
      case 'processing':
        return 'Đang xử lý';
      case 'shipped':
        return 'Đang giao';
      case 'delivered':
        return 'Đã giao';
      case 'cancelled':
        return 'Đã huỷ';
      default:
        return status;
    }
  }

  /// Human-readable payment status label (Vietnamese)
  String get paymentStatusLabel {
    switch (paymentStatus) {
      case 'unpaid':
        return 'Chưa thanh toán';
      case 'paid':
        return 'Đã thanh toán';
      case 'refunded':
        return 'Đã hoàn tiền';
      default:
        return paymentStatus;
    }
  }
}
