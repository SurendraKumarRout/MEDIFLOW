const amqplib = require('amqplib');
const logger = require('./logger');

let channel;
let connection;

const RABBITMQ_URL = process.env.RABBITMQ_URL || 'amqp://localhost';
const EXCHANGE = 'mediflow.events';

exports.connectRabbitMQ = async () => {
  connection = await amqplib.connect(RABBITMQ_URL);
  channel = await connection.createChannel();

  // Declare topic exchange — all MediFlow events go through this
  await channel.assertExchange(EXCHANGE, 'topic', { durable: true });

  logger.info(`Connected to RabbitMQ at ${RABBITMQ_URL}`);

  connection.on('error', (err) => {
    logger.error('RabbitMQ connection error:', err);
  });

  connection.on('close', () => {
    logger.warn('RabbitMQ connection closed, attempting reconnect...');
    setTimeout(exports.connectRabbitMQ, 5000);
  });
};

// Publish an event to the exchange
// routingKey: 'order.confirmed', 'order.status_updated', etc.
exports.publishEvent = async (eventType, payload) => {
  if (!channel) throw new Error('RabbitMQ channel not initialized');

  const routingKey = `order.${eventType}`;
  const message = JSON.stringify({
    eventType,
    payload,
    source: 'order-service',
    timestamp: new Date().toISOString()
  });

  channel.publish(EXCHANGE, routingKey, Buffer.from(message), { persistent: true });
  logger.info(`Event published: ${routingKey}`);
};
