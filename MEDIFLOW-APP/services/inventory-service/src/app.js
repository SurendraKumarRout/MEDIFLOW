const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { sequelize } = require('./models');
const inventoryRoutes = require('./routes/inventory.routes');
const { errorHandler } = require('./middleware/error.middleware');
const { startConsumer } = require('./controllers/inventory.controller');
const logger = require('./utils/logger');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));
app.use(express.json({ limit: '10kb' }));

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'inventory-service', timestamp: new Date().toISOString() });
});

app.use('/api/v1/inventory', inventoryRoutes);
app.use(errorHandler);

const PORT = process.env.PORT || 3006;

const startServer = async () => {
  try {
    await sequelize.authenticate();
    logger.info('Database connection established');
    await sequelize.sync({ alter: process.env.NODE_ENV === 'development' });
    await startConsumer();
    app.listen(PORT, () => logger.info(`Inventory Service running on port ${PORT}`));
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
};

startServer();
module.exports = app;
