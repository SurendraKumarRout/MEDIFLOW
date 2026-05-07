const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  const Order = sequelize.define('Order', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    orderNumber: {
      type: DataTypes.STRING,
      unique: true,
      allowNull: false
      // Format: ORD-2026-001234
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false
    },
    status: {
      type: DataTypes.ENUM(
        'PENDING_PAYMENT',
        'PAYMENT_FAILED',
        'CONFIRMED',
        'PROCESSING',
        'PACKED',
        'SHIPPED',
        'OUT_FOR_DELIVERY',
        'DELIVERED',
        'CANCELLED',
        'REFUNDED'
      ),
      defaultValue: 'PENDING_PAYMENT'
    },
    items: {
      type: DataTypes.JSONB,
      allowNull: false
      // [{ productId, productName, quantity, unitPrice, totalPrice }]
    },
    subtotal: {
      type: DataTypes.DECIMAL(10, 2),
      allowNull: false
    },
    deliveryCharge: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0
    },
    discount: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0
    },
    totalAmount: {
      type: DataTypes.DECIMAL(10, 2),
      allowNull: false
    },
    deliveryAddress: {
      type: DataTypes.JSONB,
      allowNull: false
      // { street, city, state, pincode, phone }
    },
    paymentId: {
      type: DataTypes.STRING
      // Set after payment success
    },
    trackingNumber: {
      type: DataTypes.STRING
    },
    deliveredAt: {
      type: DataTypes.DATE
    },
    statusHistory: {
      type: DataTypes.JSONB,
      defaultValue: []
      // [{ status, timestamp, note }]
    },
    notes: {
      type: DataTypes.TEXT
    }
  }, {
    tableName: 'orders',
    timestamps: true,
    hooks: {
      beforeCreate: async (order) => {
        // Generate order number: ORD-YYYY-NNNNNN
        const year = new Date().getFullYear();
        const count = await Order.count();
        order.orderNumber = `ORD-${year}-${String(count + 1).padStart(6, '0')}`;

        // Initialize status history
        order.statusHistory = [{
          status: 'PENDING_PAYMENT',
          timestamp: new Date().toISOString(),
          note: 'Order created, awaiting payment'
        }];
      }
    }
  });

  Order.prototype.addStatusEvent = async function (status, note = '') {
    const history = [...this.statusHistory, {
      status,
      timestamp: new Date().toISOString(),
      note
    }];
    await this.update({ status, statusHistory: history });
  };

  return Order;
};
