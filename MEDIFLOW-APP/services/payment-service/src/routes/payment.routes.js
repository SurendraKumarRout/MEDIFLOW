const express = require('express');
const router = express.Router();
const paymentController = require('../controllers/payment.controller');
const { authenticate } = require('../middleware/auth.middleware');

router.post('/process', authenticate, paymentController.processPayment);
router.post('/refund', authenticate, paymentController.processRefund);
router.get('/order/:orderId', authenticate, paymentController.getPaymentByOrder);

module.exports = router;
