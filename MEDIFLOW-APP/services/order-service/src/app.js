const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { sequelize } = require('./models');
const orderRoutes = require('./routes/order.routes');
const { errorHandler } = require('./middleware/error.middleware');
const { connectRabbitMQ } = require('./utils/rabbitmq');
const logger = require('./utils/logger');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));
app.use(express.json({ limit: '10kb' }));

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'order-service', timestamp: new Date().toISOString() });
});

app.use('/api/v1/orders', orderRoutes);
app.use(errorHandler);

const PORT = process.env.PORT || 3005;

const startServer = async () => {
  try {
    await sequelize.authenticate();
    logger.info('Database connection established');
    await sequelize.sync({ alter: process.env.NODE_ENV === 'development' });
    await connectRabbitMQ();
    logger.info('RabbitMQ connection established');
    app.listen(PORT, () => logger.info(`Order Service running on port ${PORT}`));
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
};

startServer();

module.exports = app;
