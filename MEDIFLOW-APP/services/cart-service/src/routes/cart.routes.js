const express = require('express');
const router = express.Router();
const cartController = require('../controllers/cart.controller');
const { authenticate } = require('../middleware/auth.middleware');

router.get('/:userId', authenticate, cartController.getCart);
router.post('/:userId/items', authenticate, cartController.addItem);
router.patch('/:userId/items/:productId', authenticate, cartController.updateItemQuantity);
router.delete('/:userId', authenticate, cartController.clearCart);

module.exports = router;
