const jwt = require("jsonwebtoken");
const { getUserById } = require("../services/authService");

async function authenticate(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : header;

  if (!token) {
    return res.status(401).json({ success: false, error: "Authorization token is required." });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET || "dev-secret");
    const user = await getUserById(decoded.id);

    if (!user) {
      return res.status(401).json({ success: false, error: "User no longer exists." });
    }

    req.user = user;
    return next();
  } catch (error) {
    return res.status(401).json({ success: false, error: "Invalid or expired token." });
  }
}

module.exports = { authenticate };
