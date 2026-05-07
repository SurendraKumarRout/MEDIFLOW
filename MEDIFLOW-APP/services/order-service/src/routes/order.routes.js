const express = require('express');
const router = express.Router();
const orderController = require('../controllers/order.controller');
const { authenticate } = require('../middleware/auth.middleware');

router.post('/', authenticate, orderController.createOrder);
router.get('/:userId', authenticate, orderController.getUserOrders);
router.get('/detail/:orderId', authenticate, orderController.getOrderById);
router.patch('/:orderId/status', authenticate, orderController.updateOrderStatus);

module.exports = router;
