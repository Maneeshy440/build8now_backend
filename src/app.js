const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
require("dotenv").config();

const authRoutes = require("./routes/authRoutes");
const shippingRoutes = require("./routes/shippingRoutes");
const loyaltyRoutes = require("./routes/loyaltyRoutes");
const orderRoutes = require("./routes/orderRoutes");

const app = express();

app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true }));

if (process.env.NODE_ENV !== "test") {
  app.use(rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 200,
    standardHeaders: true,
    legacyHeaders: false,
  }));
}

app.get("/api/health", (_req, res) => {
  res.status(200).json({ success: true, message: "Build8Now API is running" });
});

app.use("/api/auth", authRoutes);
app.use("/api", shippingRoutes);
app.use("/api", loyaltyRoutes);
app.use("/api", orderRoutes);

app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: `Route ${req.method} ${req.path} not found`,
  });
});

app.use((err, req, res, _next) => {
  console.error("Error:", err.message);
  const status = err.status || 500;
  res.status(status).json({
    success: false,
    error: err.message || "Internal server error",
  });
});

module.exports = app;