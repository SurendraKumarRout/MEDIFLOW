const amqplib = require('amqplib');
const nodemailer = require('nodemailer');
const AWS = require('aws-sdk');
const { Notification } = require('../models');
const logger = require('../utils/logger');

const RABBITMQ_URL = process.env.RABBITMQ_URL || 'amqp://localhost';
const EXCHANGE = 'mediflow.events';
const QUEUE = 'notification-service-queue';

// AWS SNS for SMS
const sns = new AWS.SNS({ region: process.env.AWS_REGION || 'ap-south-1' });

// Email transporter (SMTP or AWS SES)
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  }
});

// ── Email Templates ──────────────────────────────────────────────────────────

const orderConfirmedTemplate = (data) => ({
  subject: `MediFlow Order Confirmed — ${data.orderNumber}`,
  html: `
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto;">
      <h2 style="color: #1F4E79;">Order Confirmed! 🎉</h2>
      <p>Dear Customer,</p>
      <p>Your MediFlow order <strong>${data.orderNumber}</strong> has been confirmed.</p>
      <h3>Order Details:</h3>
      <table style="width: 100%; border-collapse: collapse;">
        ${data.items.map(item => `
          <tr>
            <td style="padding: 8px; border: 1px solid #ddd;">${item.productName}</td>
            <td style="padding: 8px; border: 1px solid #ddd;">Qty: ${item.quantity}</td>
            <td style="padding: 8px; border: 1px solid #ddd;">₹${item.totalPrice}</td>
          </tr>
        `).join('')}
      </table>
      <p><strong>Total Amount: ₹${data.totalAmount}</strong></p>
      <p>Estimated delivery: 2-3 business days</p>
      <p>Delivery Address: ${data.deliveryAddress.street}, ${data.deliveryAddress.city}, ${data.deliveryAddress.pincode}</p>
      <hr/>
      <p style="color: #595959; font-size: 12px;">MediFlow — Your Trusted Healthcare Partner</p>
    </div>
  `
});

const orderShippedTemplate = (data) => ({
  subject: `MediFlow Order Shipped — ${data.orderNumber}`,
  html: `
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto;">
      <h2 style="color: #1F4E79;">Your Order Has Shipped! 🚚</h2>
      <p>Order <strong>${data.orderNumber}</strong> is on its way.</p>
      <p>Track your order with: <strong>${data.trackingNumber}</strong></p>
    </div>
  `
});

// ── SMS Templates ────────────────────────────────────────────────────────────

const smsTemplates = {
  order_confirmed: (data) =>
    `MediFlow: Your order ${data.orderNumber} confirmed! Total: Rs.${data.totalAmount}. Expected delivery: 2-3 days.`,
  order_shipped: (data) =>
    `MediFlow: Order ${data.orderNumber} shipped! Track: ${data.trackingNumber}`,
  order_delivered: (data) =>
    `MediFlow: Order ${data.orderNumber} delivered! Thank you for choosing MediFlow.`
};

// ── Send Helpers ─────────────────────────────────────────────────────────────

const sendEmail = async (to, template) => {
  await transporter.sendMail({
    from: `"MediFlow" <${process.env.FROM_EMAIL}>`,
    to,
    subject: template.subject,
    html: template.html
  });
  logger.info(`Email sent to ${to}: ${template.subject}`);
};

const sendSMS = async (phone, message) => {
  await sns.publish({
    Message: message,
    PhoneNumber: `+91${phone}`, // Indian number format
    MessageAttributes: {
      'AWS.SNS.SMS.SMSType': { DataType: 'String', StringValue: 'Transactional' }
    }
  }).promise();
  logger.info(`SMS sent to ${phone}`);
};

// ── Event Handlers ────────────────────────────────────────────────────────────

const handleOrderConfirmed = async (payload) => {
  const { orderId, orderNumber, userId, items, totalAmount, deliveryAddress } = payload;

  // In a real system, fetch user email/phone from User Service
  const userEmail = payload.userEmail || 'customer@example.com';
  const userPhone = payload.userPhone || '9876543210';

  try {
    await sendEmail(userEmail, orderConfirmedTemplate({ orderNumber, items, totalAmount, deliveryAddress }));
    await sendSMS(userPhone, smsTemplates.order_confirmed({ orderNumber, totalAmount }));

    await Notification.create({
      userId, orderId, type: 'ORDER_CONFIRMED',
      channel: 'EMAIL_SMS', status: 'SENT',
      metadata: { orderNumber, totalAmount }
    });
  } catch (error) {
    logger.error(`Failed to send order_confirmed notification for ${orderNumber}:`, error.message);
    await Notification.create({
      userId, orderId, type: 'ORDER_CONFIRMED',
      channel: 'EMAIL_SMS', status: 'FAILED',
      error: error.message
    });
  }
};

const handleOrderStatusUpdated = async (payload) => {
  const { orderId, orderNumber, userId, status, trackingNumber } = payload;

  try {
    if (status === 'SHIPPED') {
      const userPhone = payload.userPhone || '9876543210';
      await sendSMS(userPhone, smsTemplates.order_shipped({ orderNumber, trackingNumber }));
    }

    await Notification.create({
      userId, orderId, type: `ORDER_${status}`,
      channel: 'SMS', status: 'SENT',
      metadata: { orderNumber, trackingNumber }
    });
  } catch (error) {
    logger.error(`Failed to send status notification for ${orderNumber}:`, error.message);
  }
};

// ── RabbitMQ Consumer ─────────────────────────────────────────────────────────

exports.startConsumer = async () => {
  const connection = await amqplib.connect(RABBITMQ_URL);
  const channel = await connection.createChannel();

  await channel.assertExchange(EXCHANGE, 'topic', { durable: true });
  await channel.assertQueue(QUEUE, { durable: true });

  // Bind to order events
  await channel.bindQueue(QUEUE, EXCHANGE, 'order.order_confirmed');
  await channel.bindQueue(QUEUE, EXCHANGE, 'order.order_status_updated');

  // Process one message at a time
  channel.prefetch(1);

  channel.consume(QUEUE, async (msg) => {
    if (!msg) return;

    try {
      const event = JSON.parse(msg.content.toString());
      logger.info(`Received event: ${event.eventType}`);

      switch (event.eventType) {
        case 'order_confirmed':
          await handleOrderConfirmed(event.payload);
          break;
        case 'order_status_updated':
          await handleOrderStatusUpdated(event.payload);
          break;
        default:
          logger.warn(`Unknown event type: ${event.eventType}`);
      }

      channel.ack(msg);
    } catch (error) {
      logger.error('Error processing message:', error);
      // Nack and requeue for retry
      channel.nack(msg, false, true);
    }
  });

  logger.info('Notification Service consumer started, listening for order events...');
};
