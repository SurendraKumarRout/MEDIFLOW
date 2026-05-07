const redis = require('redis');
const logger = require('./logger');

const client = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

client.on('error', (err) => logger.error('Redis client error:', err));
client.on('connect', () => logger.info('Connected to Redis'));

client.connect();

module.exports = client;
