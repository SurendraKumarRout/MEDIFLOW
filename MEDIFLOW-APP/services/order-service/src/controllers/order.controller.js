const axios = require('axios');
const { Order } = require('../models');
const { publishEvent } = require('../utils/rabbitmq');
const { AppError } = require('../middleware/error.middleware');
const logger = require('../utils/logger');

const PAYMENT_SERVICE_URL = process.env.PAYMENT_SERVICE_URL;
const INVENTORY_SERVICE_URL = process.env.INVENTORY_SERVICE_URL;
const CART_SERVICE_URL = process.env.CART_SERVICE_URL;

// POST /api/v1/orders
// Called when Rajesh clicks "Place Order"
exports.createOrder = async (req, res, next) => {
  try {
    const { userId, items, deliveryAddress, paymentToken } = req.body;

    if (!items || items.length === 0) {
      return next(new AppError('Order must have at least one item', 400));
    }

    // Step 1: Verify inventory availability for all items
    logger.info(`Checking inventory for order by user ${userId}`);
    for (const item of items) {
      const inventoryRes = await axios.get(
        `${INVENTORY_SERVICE_URL}/api/v1/inventory/${item.productId}`
      );
      const { availableQuantity } = inventoryRes.data.data;

      if (availableQuantity < item.quantity) {
        return next(new AppError(
          `Insufficient stock for product ${item.productName}. Available: ${availableQuantity}`,
          409
        ));
      }
    }

    // Step 2: Calculate totals
    const subtotal = items.reduce((sum, item) => sum + (item.unitPrice * item.quantity), 0);
    const deliveryCharge = subtotal >= 500 ? 0 : 49; // Free delivery above ₹500
    const totalAmount = subtotal + deliveryCharge;

    // Step 3: Create order in PENDING_PAYMENT state
    const order = await Order.create({
      userId,
      items,
      subtotal,
      deliveryCharge,
      totalAmount,
      deliveryAddress
    });

    logger.info(`Order created: ${order.orderNumber}, total: ₹${totalAmount}`);

    // Step 4: Process payment
    logger.info(`Processing payment for order ${order.orderNumber}`);
    let paymentResult;
    try {
      const paymentRes = await axios.post(`${PAYMENT_SERVICE_URL}/api/v1/payments/process`, {
        orderId: order.id,
        orderNumber: order.orderNumber,
        amount: totalAmount,
        currency: 'INR',
        paymentToken,
        userId
      });
      paymentResult = paymentRes.data.data;
    } catch (paymentError) {
      // Payment failed — update order status and return error
      await order.addStatusEvent('PAYMENT_FAILED', paymentError.response?.data?.message || 'Payment processing failed');
      logger.error(`Payment failed for order ${order.orderNumber}:`, paymentError.message);
      return next(new AppError('Payment failed. Please try again.', 402));
    }

    // Step 5: Payment success — confirm order
    await order.update({ paymentId: paymentResult.transactionId });
    await order.addStatusEvent('CONFIRMED', `Payment successful. Transaction: ${paymentResult.transactionId}`);

    logger.info(`Order confirmed: ${order.orderNumber}, transaction: ${paymentResult.transactionId}`);

    // Step 6: Clear user's cart
    await axios.delete(`${CART_SERVICE_URL}/api/v1/cart/${userId}`).catch(err => {
      // Non-critical — log but don't fail the order
      logger.warn(`Failed to clear cart for user ${userId}: ${err.message}`);
    });

    // Step 7: Publish order_confirmed event to RabbitMQ
    // Notification Service and Inventory Service will react to this
    await publishEvent('order_confirmed', {
      orderId: order.id,
      orderNumber: order.orderNumber,
      userId,
      items,
      totalAmount,
      deliveryAddress,
      timestamp: new Date().toISOString()
    });

    logger.info(`Published order_confirmed event for ${order.orderNumber}`);

    res.status(201).json({
      status: 'success',
      data: { order }
    });
  } catch (error) {
    next(error);
  }
};

// GET /api/v1/orders/:userId
// Rajesh checks his order history
exports.getUserOrders = async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { page = 1, limit = 10, status } = req.query;

    const where = { userId };
    if (status) where.status = status;

    const offset = (page - 1) * limit;
    const { count, rows: orders } = await Order.findAndCountAll({
      where,
      order: [['createdAt', 'DESC']],
      limit: parseInt(limit),
      offset
    });

    res.status(200).json({
      status: 'success',
      data: {
        orders,
        pagination: {
          total: count,
          page: parseInt(page),
          limit: parseInt(limit),
          pages: Math.ceil(count / limit)
        }
      }
    });
  } catch (error) {
    next(error);
  }
};

// GET /api/v1/orders/detail/:orderId
exports.getOrderById = async (req, res, next) => {
  try {
    const order = await Order.findByPk(req.params.orderId);
    if (!order) return next(new AppError('Order not found', 404));

    res.status(200).json({ status: 'success', data: { order } });
  } catch (error) {
    next(error);
  }
};

// PATCH /api/v1/orders/:orderId/status
// Called by warehouse/delivery systems to update status
exports.updateOrderStatus = async (req, res, next) => {
  try {
    const { status, note, trackingNumber } = req.body;
    const order = await Order.findByPk(req.params.orderId);
    if (!order) return next(new AppError('Order not found', 404));

    const updateData = {};
    if (trackingNumber) updateData.trackingNumber = trackingNumber;
    if (status === 'DELIVERED') updateData.deliveredAt = new Date();

    if (Object.keys(updateData).length > 0) await order.update(updateData);
    await order.addStatusEvent(status, note);

    // Publish status update event for Notification Service
    await publishEvent('order_status_updated', {
      orderId: order.id,
      orderNumber: order.orderNumber,
      userId: order.userId,
      status,
      trackingNumber,
      note,
      timestamp: new Date().toISOString()
    });

    logger.info(`Order ${order.orderNumber} status updated to ${status}`);

    res.status(200).json({ status: 'success', data: { order } });
  } catch (error) {
    next(error);
  }
};
