const express = require("express");
const ctrl = require("../controllers/shippingController");
const { authenticate } = require("../middleware/authMiddleware");
const { authorize } = require("../middleware/roleMiddleware");

const router = express.Router();

router.post("/shipping/calculate", authenticate, ctrl.calculate);

router.post("/admin/shipping-profiles",
  authenticate, authorize("ADMIN"), ctrl.create);
router.get("/admin/shipping-profiles",
  authenticate, authorize("ADMIN"), ctrl.list);
router.get("/admin/shipping-profiles/:id",
  authenticate, authorize("ADMIN"), ctrl.getOne);
router.delete("/admin/shipping-profiles/:id",
  authenticate, authorize("ADMIN"), ctrl.deactivate);

router.put("/admin/products/:productId/shipping-profile",
  authenticate, authorize("ADMIN"), ctrl.assign);

module.exports = router;