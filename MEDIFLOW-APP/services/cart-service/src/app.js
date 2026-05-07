const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const cartRoutes = require('./routes/cart.routes');
const { errorHandler } = require('./middleware/error.middleware');
const logger = require('./utils/logger');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));
app.use(express.json({ limit: '10kb' }));

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'cart-service', timestamp: new Date().toISOString() });
});

app.use('/api/v1/cart', cartRoutes);
app.use(errorHandler);

const PORT = process.env.PORT || 3003;

app.listen(PORT, () => logger.info(`Cart Service running on port ${PORT}`));
module.exports = app;
