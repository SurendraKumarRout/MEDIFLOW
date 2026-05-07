const jwt = require('jsonwebtoken');
const { User } = require('../models');
const { AppError } = require('../middleware/error.middleware');
const logger = require('../utils/logger');

// Generate JWT token
const generateToken = (userId, role) => {
  return jwt.sign(
    { userId, role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '24h' }
  );
};

// POST /api/v1/auth/register
exports.register = async (req, res, next) => {
  try {
    const { firstName, lastName, email, phone, password } = req.body;

    // Check if user already exists
    const existingUser = await User.findOne({ where: { email } });
    if (existingUser) {
      return next(new AppError('Email already registered', 409));
    }

    const user = await User.create({ firstName, lastName, email, phone, password });

    const token = generateToken(user.id, user.role);

    logger.info(`New user registered: ${user.email}`);

    res.status(201).json({
      status: 'success',
      token,
      data: { user: user.toSafeJSON() }
    });
  } catch (error) {
    next(error);
  }
};

// POST /api/v1/auth/login
exports.login = async (req, res, next) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return next(new AppError('Email and password are required', 400));
    }

    const user = await User.findOne({ where: { email, isActive: true } });

    if (!user || !(await user.validatePassword(password))) {
      return next(new AppError('Invalid email or password', 401));
    }

    // Update last login timestamp
    await user.update({ lastLoginAt: new Date() });

    const token = generateToken(user.id, user.role);

    logger.info(`User logged in: ${user.email}`);

    res.status(200).json({
      status: 'success',
      token,
      data: { user: user.toSafeJSON() }
    });
  } catch (error) {
    next(error);
  }
};

// POST /api/v1/auth/verify-token
// Called by other microservices to validate JWT
exports.verifyToken = async (req, res, next) => {
  try {
    const { token } = req.body;

    if (!token) {
      return next(new AppError('Token is required', 400));
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await User.findOne({
      where: { id: decoded.userId, isActive: true },
      attributes: ['id', 'email', 'firstName', 'lastName', 'role', 'isVerified']
    });

    if (!user) {
      return next(new AppError('User not found or inactive', 404));
    }

    res.status(200).json({
      status: 'success',
      data: { user, isValid: true }
    });
  } catch (error) {
    if (error.name === 'JsonWebTokenError' || error.name === 'TokenExpiredError') {
      return next(new AppError('Invalid or expired token', 401));
    }
    next(error);
  }
};
