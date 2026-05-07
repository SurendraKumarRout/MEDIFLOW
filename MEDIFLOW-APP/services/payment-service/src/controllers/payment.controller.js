const Stripe = require('stripe');
const { Payment } = require('../models');
const { AppError } = require('../middleware/error.middleware');
const logger = require('../utils/logger');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

// POST /api/v1/payments/process
// Called by Order Service to charge the customer
exports.processPayment = async (req, res, next) => {
  try {
    const { orderId, orderNumber, amount, currency, paymentToken, userId } = req.body;

    logger.info(`Processing payment for order ${orderNumber}: ₹${amount}`);

    // Convert to smallest currency unit (paise for INR)
    const amountInPaise = Math.round(amount * 100);

    // Create Stripe PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInPaise,
      currency: currency.toLowerCase(), // 'inr'
      payment_method: paymentToken,
      confirm: true,
      metadata: {
        orderId,
        orderNumber,
        userId
      },
      description: `MediFlow Order ${orderNumber}`
    });

    if (paymentIntent.status !== 'succeeded') {
      throw new AppError(`Payment not completed. Status: ${paymentIntent.status}`, 402);
    }

    // Record payment in our database
    const payment = await Payment.create({
      orderId,
      orderNumber,
      userId,
      amount,
      currency,
      status: 'SUCCESS',
      transactionId: paymentIntent.id,
      stripePaymentIntentId: paymentIntent.id,
      paymentMethod: paymentIntent.payment_method_types[0],
      metadata: {
        stripeStatus: paymentIntent.status,
        receiptUrl: paymentIntent.charges?.data[0]?.receipt_url
      }
    });

    logger.info(`Payment successful: ${payment.transactionId} for order ${orderNumber}`);

    res.status(200).json({
      status: 'success',
      data: {
        transactionId: payment.transactionId,
        amount,
        currency,
        status: 'SUCCESS'
      }
    });
  } catch (error) {
    // Handle Stripe-specific errors
    if (error.type === 'StripeCardError') {
      logger.warn(`Card declined for order ${req.body.orderNumber}: ${error.message}`);
      return next(new AppError(`Card declined: ${error.message}`, 402));
    }
    if (error.type === 'StripeInvalidRequestError') {
      logger.error('Invalid Stripe request:', error.message);
      return next(new AppError('Payment configuration error', 500));
    }
    next(error);
  }
};

// POST /api/v1/payments/refund
exports.processRefund = async (req, res, next) => {
  try {
    const { orderId, reason } = req.body;

    const payment = await Payment.findOne({ where: { orderId, status: 'SUCCESS' } });
    if (!payment) return next(new AppError('No successful payment found for this order', 404));

    const refund = await stripe.refunds.create({
      payment_intent: payment.stripePaymentIntentId,
      reason: 'requested_by_customer'
    });

    await payment.update({
      status: 'REFUNDED',
      refundId: refund.id,
      refundReason: reason
    });

    logger.info(`Refund processed: ${refund.id} for order ${payment.orderNumber}`);

    res.status(200).json({
      status: 'success',
      data: { refundId: refund.id, status: 'REFUNDED' }
    });
  } catch (error) {
    next(error);
  }
};

// GET /api/v1/payments/order/:orderId
exports.getPaymentByOrder = async (req, res, next) => {
  try {
    const payment = await Payment.findOne({ where: { orderId: req.params.orderId } });
    if (!payment) return next(new AppError('Payment not found', 404));
    res.status(200).json({ status: 'success', data: { payment } });
  } catch (error) {
    next(error);
  }
};
