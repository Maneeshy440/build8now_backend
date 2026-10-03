const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
require("dotenv").config();

const authRoutes = require("./routes/authRoutes");

const app = express();

app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true }));

app.use("/api/auth", authRoutes);
app.use("/api", require("./routes/shippingRoutes"));
app.use("/api/auth", require("./routes/authRoutes"));
app.use("/api", require("./routes/shippingRoutes"));
app.use("/api", require("./routes/loyaltyRoutes"));   
app.use("/api", require("./routes/orderRoutes")); 

// Rate limit only in non-test
if (process.env.NODE_ENV !== "test") {
  app.use(rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 200,
    standardHeaders: true,
    legacyHeaders: false,
  }));
}

app.get("/api/health", (req, res) => {
  res.status(200).json({ success: true, message: "Build8Now API is running" });
});

app.use("/api/auth", authRoutes);

// 404
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: `Route ${req.method} ${req.path} not found`,
  });
});

// Global error handler
app.use((err, req, res, _next) => {
  console.error("Error:", err.message);
  const status = err.status || 500;
  res.status(status).json({
    success: false,
    error: err.message || "Internal server error",
  });
});

module.exports = app;