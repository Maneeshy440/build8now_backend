const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { pool } = require("../config/db");

const BCRYPT_ROUNDS = 12;

function signToken(user) {
  return jwt.sign(
    { id: user.id, email: user.email, role: user.role },
    process.env.JWT_SECRET || "dev-secret",
    { expiresIn: process.env.JWT_ACCESS_EXPIRES || "15m" }  
  );
}

const ALLOWED_ROLES = ["ADMIN", "CUSTOMER", "INFLUENCER"];

async function registerUser({ full_name, email, password, role = "CUSTOMER", phone = null }) {
  if (!full_name || !email || !password) {
    const err = new Error("full_name, email, and password are required.");
    err.status = 400;
    throw err;
  }

  const normalizedEmail = String(email).trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
    const err = new Error("Please provide a valid email address.");
    err.status = 400;
    throw err;
  }

  const normalizedRole = String(role).toUpperCase();
  if (!ALLOWED_ROLES.includes(normalizedRole)) {
    const err = new Error(`Invalid role. Allowed: ${ALLOWED_ROLES.join(", ")}`);
    err.status = 400;
    throw err;
  }

  if (normalizedRole === "ADMIN") {
    const err = new Error("Admin registration is not allowed.");
    err.status = 403;
    throw err;
  }

  const [existing] = await pool.execute(
    "SELECT id FROM users WHERE email = ? LIMIT 1",
    [normalizedEmail]
  );
  if (existing.length) {
    const err = new Error("Email already registered.");
    err.status = 409;
    throw err;
  }

  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

  const [result] = await pool.execute(
    `INSERT INTO users (email, password_hash, full_name, phone, role)
     VALUES (?, ?, ?, ?, ?)`,
    [normalizedEmail, passwordHash, String(full_name).trim(), phone, normalizedRole]
  );

  return getUserById(result.insertId);
}

async function loginUser({ email, password }) {
  if (!email || !password) {
    const err = new Error("Email and password are required.");
    err.status = 400;
    throw err;
  }

  const [rows] = await pool.execute(
    `SELECT id, email, password_hash, full_name, phone, role, is_active, created_at
     FROM users WHERE email = ? LIMIT 1`,
    [String(email).trim().toLowerCase()]
  );

  if (!rows.length) {
    const err = new Error("Invalid email or password.");
    err.status = 401;
    throw err;
  }

  const user = rows[0];

  if (!user.is_active) {
    const err = new Error("Account is disabled.");
    err.status = 401;
    throw err;
  }

  const isValidPassword = await bcrypt.compare(password, user.password_hash);
  if (!isValidPassword) {
    const err = new Error("Invalid email or password.");
    err.status = 401;
    throw err;
  }

  const token = signToken(user);

  return {
    token,
    user: {
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      phone: user.phone,
      role: user.role,
    },
  };
}

async function getUserById(id) {
  const [rows] = await pool.execute(
    `SELECT id, email, full_name, phone, role, is_active, created_at
     FROM users WHERE id = ? LIMIT 1`,
    [id]
  );
  return rows[0] || null;
}

module.exports = {
  registerUser,
  loginUser,
  getUserById,
  signToken,
};