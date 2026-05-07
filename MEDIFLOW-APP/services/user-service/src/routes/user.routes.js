const express = require('express');
const router = express.Router();
const { authenticate } = require('../middleware/auth.middleware');

router.get('/profile', authenticate, (req, res) => {
  res.status(200).json({ status: 'success', data: { user: req.user } });
});

module.exports = router;
