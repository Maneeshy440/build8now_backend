const express = require("express");
const ctrl = require("../controllers/loyaltyController");
const { authenticate } = require("../middleware/authMiddleware");
const { authorize } = require("../middleware/roleMiddleware");

const router = express.Router();

router.get("/influencers/me/balance",
  authenticate, authorize("INFLUENCER"), ctrl.balance);

router.get("/influencers/me/ledger",
  authenticate, authorize("INFLUENCER"), ctrl.ledger);

router.get("/influencers/me/referred-customers",
  authenticate, authorize("INFLUENCER"), ctrl.referredCustomers);

module.exports = router;