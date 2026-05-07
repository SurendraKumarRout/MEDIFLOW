const express = require('express');
const router = express.Router();
const productController = require('../controllers/product.controller');
const { authenticate, authorize } = require('../middleware/auth.middleware');

router.get('/', productController.getProducts);
router.get('/:id', productController.getProductById);
router.post('/', authenticate, authorize('admin', 'pharmacist'), productController.createProduct);
router.patch('/:id', authenticate, authorize('admin', 'pharmacist'), productController.updateProduct);

module.exports = router;
