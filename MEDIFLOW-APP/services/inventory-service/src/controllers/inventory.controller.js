const amqplib = require('amqplib');
const { Inventory } = require('../models');
const { AppError } = require('../middleware/error.middleware');
const logger = require('../utils/logger');

const RABBITMQ_URL = process.env.RABBITMQ_URL || 'amqp://localhost';
const EXCHANGE = 'mediflow.events';
const QUEUE = 'inventory-service-queue';

// GET /api/v1/inventory/:productId
// Called by Product Service to show stock status
exports.getInventory = async (req, res, next) => {
  try {
    const inventory = await Inventory.findOne({ where: { productId: req.params.productId } });
    if (!inventory) return next(new AppError('Inventory record not found', 404));

    res.status(200).json({
      status: 'success',
      data: {
        productId: inventory.productId,
        availableQuantity: inventory.availableQuantity,
        reservedQuantity: inventory.reservedQuantity,
        warehouseLocation: inventory.warehouseLocation,
        isInStock: inventory.availableQuantity > 0,
        lowStockAlert: inventory.availableQuantity <= inventory.lowStockThreshold
      }
    });
  } catch (error) {
    next(error);
  }
};

// PUT /api/v1/inventory/:productId/stock
// Admin updates stock after restocking
exports.updateStock = async (req, res, next) => {
  try {
    const { quantity, operation } = req.body;
    // operation: 'add' | 'set'

    const inventory = await Inventory.findOne({ where: { productId: req.params.productId } });
    if (!inventory) return next(new AppError('Inventory record not found', 404));

    if (operation === 'add') {
      await inventory.increment('availableQuantity', { by: quantity });
    } else if (operation === 'set') {
      await inventory.update({ availableQuantity: quantity });
    }

    logger.info(`Stock updated for product ${req.params.productId}: ${operation} ${quantity}`);

    await inventory.reload();
    res.status(200).json({ status: 'success', data: { inventory } });
  } catch (error) {
    next(error);
  }
};

// ── RabbitMQ Consumer ─────────────────────────────────────────────────────────
// Listens for order_confirmed events and decrements stock

exports.startConsumer = async () => {
  const connection = await amqplib.connect(RABBITMQ_URL);
  const channel = await connection.createChannel();

  await channel.assertExchange(EXCHANGE, 'topic', { durable: true });
  await channel.assertQueue(QUEUE, { durable: true });
  await channel.bindQueue(QUEUE, EXCHANGE, 'order.order_confirmed');

  channel.prefetch(1);

  channel.consume(QUEUE, async (msg) => {
    if (!msg) return;

    try {
      const event = JSON.parse(msg.content.toString());

      if (event.eventType === 'order_confirmed') {
        const { orderNumber, items } = event.payload;
        logger.info(`Decrementing stock for order ${orderNumber}`);

        // Decrement stock for each item in the order
        for (const item of items) {
          const inventory = await Inventory.findOne({ where: { productId: item.productId } });

          if (inventory) {
            if (inventory.availableQuantity < item.quantity) {
              // This should not happen (Order Service checks first), but handle gracefully
              logger.error(`Insufficient stock for ${item.productName} in order ${orderNumber}`);
            } else {
              await inventory.decrement('availableQuantity', { by: item.quantity });
              logger.info(`Stock decremented: ${item.productName} -${item.quantity}`);

              // Check low stock alert
              await inventory.reload();
              if (inventory.availableQuantity <= inventory.lowStockThreshold) {
                logger.warn(`LOW STOCK ALERT: ${item.productName} — ${inventory.availableQuantity} units remaining`);
                // In production: trigger a notification to procurement team
              }
            }
          }
        }
      }

      channel.ack(msg);
    } catch (error) {
      logger.error('Error processing inventory event:', error);
      channel.nack(msg, false, true);
    }
  });

  logger.info('Inventory Service consumer started, listening for order events...');
};
