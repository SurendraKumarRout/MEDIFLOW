const redis = require('../utils/redis');
const axios = require('axios');
const { AppError } = require('../middleware/error.middleware');
const logger = require('../utils/logger');

const PRODUCT_SERVICE_URL = process.env.PRODUCT_SERVICE_URL;
const CART_TTL = 7 * 24 * 60 * 60; // 7 days in seconds

const getCartKey = (userId) => `cart:${userId}`;

// GET /api/v1/cart/:userId
exports.getCart = async (req, res, next) => {
  try {
    const cartData = await redis.get(getCartKey(req.params.userId));
    const cart = cartData ? JSON.parse(cartData) : { items: [], updatedAt: null };

    // Calculate totals
    const subtotal = cart.items.reduce((sum, item) => sum + (item.unitPrice * item.quantity), 0);
    const deliveryCharge = subtotal >= 500 ? 0 : 49;
    const totalAmount = subtotal + deliveryCharge;

    res.status(200).json({
      status: 'success',
      data: { cart: { ...cart, subtotal, deliveryCharge, totalAmount } }
    });
  } catch (error) {
    next(error);
  }
};

// POST /api/v1/cart/:userId/items
// Rajesh clicks "Add to Cart"
exports.addItem = async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { productId, quantity } = req.body;

    if (quantity < 1) return next(new AppError('Quantity must be at least 1', 400));

    // Fetch product details from Product Service
    const productRes = await axios.get(`${PRODUCT_SERVICE_URL}/api/v1/products/${productId}`);
    const product = productRes.data.data.product;

    if (!product.isAvailable) {
      return next(new AppError('Product is not available', 409));
    }

    // Get existing cart
    const cartData = await redis.get(getCartKey(userId));
    const cart = cartData ? JSON.parse(cartData) : { items: [] };

    // Check if item already in cart
    const existingIndex = cart.items.findIndex(i => i.productId === productId);

    if (existingIndex >= 0) {
      // Update quantity
      cart.items[existingIndex].quantity += quantity;
      cart.items[existingIndex].totalPrice = cart.items[existingIndex].unitPrice * cart.items[existingIndex].quantity;
    } else {
      // Add new item
      cart.items.push({
        productId,
        productName: product.name,
        unitPrice: product.price,
        quantity,
        totalPrice: product.price * quantity,
        imageUrl: product.imageUrl,
        manufacturer: product.manufacturer
      });
    }

    cart.updatedAt = new Date().toISOString();

    // Save back to Redis with TTL
    await redis.setex(getCartKey(userId), CART_TTL, JSON.stringify(cart));

    logger.info(`Item added to cart for user ${userId}: ${product.name} x${quantity}`);

    res.status(200).json({ status: 'success', data: { cart } });
  } catch (error) {
    next(error);
  }
};

// PATCH /api/v1/cart/:userId/items/:productId
exports.updateItemQuantity = async (req, res, next) => {
  try {
    const { userId, productId } = req.params;
    const { quantity } = req.body;

    const cartData = await redis.get(getCartKey(userId));
    if (!cartData) return next(new AppError('Cart not found', 404));

    const cart = JSON.parse(cartData);
    const itemIndex = cart.items.findIndex(i => i.productId === productId);
    if (itemIndex === -1) return next(new AppError('Item not found in cart', 404));

    if (quantity === 0) {
      cart.items.splice(itemIndex, 1);
    } else {
      cart.items[itemIndex].quantity = quantity;
      cart.items[itemIndex].totalPrice = cart.items[itemIndex].unitPrice * quantity;
    }

    cart.updatedAt = new Date().toISOString();
    await redis.setex(getCartKey(userId), CART_TTL, JSON.stringify(cart));

    res.status(200).json({ status: 'success', data: { cart } });
  } catch (error) {
    next(error);
  }
};

// DELETE /api/v1/cart/:userId
// Called by Order Service after successful order placement
exports.clearCart = async (req, res, next) => {
  try {
    await redis.del(getCartKey(req.params.userId));
    logger.info(`Cart cleared for user ${req.params.userId}`);
    res.status(200).json({ status: 'success', message: 'Cart cleared' });
  } catch (error) {
    next(error);
  }
};
