const express = require('express');
const router = express.Router();
const inventoryController = require('../controllers/inventory.controller');
const { authenticate, authorize } = require('../middleware/auth.middleware');

router.get('/:productId', inventoryController.getInventory);
router.put('/:productId/stock', authenticate, authorize('admin'), inventoryController.updateStock);

module.exports = router;
