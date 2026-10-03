const express = require("express");
const ctrl = require("../controllers/orderController");
const { authenticate } = require("../middleware/authMiddleware");

const router = express.Router();

router.post("/orders", authenticate, ctrl.create);
router.get("/orders", authenticate, ctrl.list);
router.get("/orders/:id", authenticate, ctrl.getOne);
router.post("/orders/:id/cancel", authenticate, ctrl.cancel);

module.exports = router;