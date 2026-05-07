const axios = require('axios');
const { Product, Category } = require('../models');
const { AppError } = require('../middleware/error.middleware');
const logger = require('../utils/logger');

const INVENTORY_SERVICE_URL = process.env.INVENTORY_SERVICE_URL;

// GET /api/v1/products
// Rajesh browses or searches products
exports.getProducts = async (req, res, next) => {
  try {
    const {
      search, category, minPrice, maxPrice,
      sortBy = 'name', sortOrder = 'ASC',
      page = 1, limit = 20
    } = req.query;

    const { Op } = require('sequelize');
    const where = { isAvailable: true };

    if (search) {
      where[Op.or] = [
        { name: { [Op.iLike]: `%${search}%` } },
        { genericName: { [Op.iLike]: `%${search}%` } },
        { manufacturer: { [Op.iLike]: `%${search}%` } }
      ];
    }

    if (category) where.categoryId = category;
    if (minPrice) where.price = { ...where.price, [Op.gte]: minPrice };
    if (maxPrice) where.price = { ...where.price, [Op.lte]: maxPrice };

    const offset = (page - 1) * limit;
    const { count, rows: products } = await Product.findAndCountAll({
      where,
      include: [{ model: Category, attributes: ['id', 'name'] }],
      order: [[sortBy, sortOrder]],
      limit: parseInt(limit),
      offset
    });

    // Fetch inventory status for each product (batch call)
    const productIds = products.map(p => p.id);
    let inventoryMap = {};

    try {
      const inventoryRes = await axios.post(
        `${INVENTORY_SERVICE_URL}/api/v1/inventory/batch`,
        { productIds }
      );
      inventoryMap = inventoryRes.data.data.inventory;
    } catch (err) {
      // If inventory service is down, still return products (degraded mode)
      logger.warn('Inventory service unavailable, returning products without stock info');
    }

    const productsWithStock = products.map(p => ({
      ...p.toJSON(),
      isInStock: inventoryMap[p.id]?.isInStock ?? true,
      availableQuantity: inventoryMap[p.id]?.availableQuantity ?? null
    }));

    res.status(200).json({
      status: 'success',
      data: {
        products: productsWithStock,
        pagination: { total: count, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(count / limit) }
      }
    });
  } catch (error) {
    next(error);
  }
};

// GET /api/v1/products/:id
// Rajesh views product detail page
exports.getProductById = async (req, res, next) => {
  try {
    const product = await Product.findOne({
      where: { id: req.params.id, isAvailable: true },
      include: [{ model: Category, attributes: ['id', 'name', 'description'] }]
    });

    if (!product) return next(new AppError('Product not found', 404));

    // Fetch real-time inventory
    let stockInfo = {};
    try {
      const inventoryRes = await axios.get(`${INVENTORY_SERVICE_URL}/api/v1/inventory/${product.id}`);
      stockInfo = inventoryRes.data.data;
    } catch (err) {
      logger.warn(`Could not fetch inventory for product ${product.id}`);
    }

    res.status(200).json({
      status: 'success',
      data: {
        product: { ...product.toJSON(), ...stockInfo }
      }
    });
  } catch (error) {
    next(error);
  }
};

// POST /api/v1/products — Admin adds new medicine
exports.createProduct = async (req, res, next) => {
  try {
    const {
      name, genericName, description, manufacturer,
      price, categoryId, composition, dosage,
      sideEffects, storageInstructions, requiresPrescription,
      imageUrl, batchNumber, expiryDate
    } = req.body;

    const product = await Product.create({
      name, genericName, description, manufacturer,
      price, categoryId, composition, dosage,
      sideEffects, storageInstructions, requiresPrescription,
      imageUrl, batchNumber, expiryDate
    });

    logger.info(`New product added: ${product.name} by ${req.user?.email}`);

    res.status(201).json({ status: 'success', data: { product } });
  } catch (error) {
    next(error);
  }
};

// PATCH /api/v1/products/:id
exports.updateProduct = async (req, res, next) => {
  try {
    const product = await Product.findByPk(req.params.id);
    if (!product) return next(new AppError('Product not found', 404));

    await product.update(req.body);
    logger.info(`Product updated: ${product.name}`);

    res.status(200).json({ status: 'success', data: { product } });
  } catch (error) {
    next(error);
  }
};
