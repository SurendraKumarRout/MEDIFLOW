const logger = require('../utils/logger');

class AppError extends Error {
  constructor(message, statusCode) {
    super(message);
    this.statusCode = statusCode;
    this.status = `${statusCode}`.startsWith('4') ? 'fail' : 'error';
    this.isOperational = true;
    Error.captureStackTrace(this, this.constructor);
  }
}

const errorHandler = (err, req, res, next) => {
  err.statusCode = err.statusCode || 500;
  err.status = err.status || 'error';

  if (err.statusCode >= 500) {
    logger.error({ message: err.message, stack: err.stack, path: req.path, method: req.method });
  } else {
    logger.warn({ message: err.message, path: req.path, statusCode: err.statusCode });
  }

  if (err.name === 'SequelizeValidationError') {
    const errors = err.errors.map(e => ({ field: e.path, message: e.message }));
    return res.status(422).json({ status: 'fail', message: 'Validation failed', errors });
  }

  if (err.name === 'SequelizeUniqueConstraintError') {
    return res.status(409).json({ status: 'fail', message: 'A record with this value already exists' });
  }

  if (err.isOperational) {
    return res.status(err.statusCode).json({ status: err.status, message: err.message });
  }

  return res.status(500).json({ status: 'error', message: 'Something went wrong. Please try again.' });
};

module.exports = { AppError, errorHandler };
