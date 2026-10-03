const express = require("express");
const { registerUser, loginUser, getUserById } = require("../services/authService");
const { authenticate } = require("../middleware/authMiddleware");

const router = express.Router();

router.post("/register", async (req, res, next) => {
  try {
    const user = await registerUser(req.body || {});
    res.status(201).json({ success: true, data: user });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message || "Unable to register user." });
  }
});

router.post("/login", async (req, res, next) => {
  try {
    const result = await loginUser(req.body || {});
    res.status(200).json({ success: true, data: result });
  } catch (error) {
    next(error);  // ← let global error handler send proper status (401/400)
  }
});

router.get("/me", authenticate, async (req, res, next) => {
  try {
    const user = await getUserById(req.user.id);
    if (!user) return res.status(404).json({ success: false, error: "User not found" });
    res.status(200).json({ success: true, data: user });
  } catch (error) {
    next(error);
  }
});

module.exports = router;