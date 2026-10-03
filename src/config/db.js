require("dotenv").config();
const mysql = require("mysql2/promise");

const pool = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "build8now",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  multipleStatements: false,
  charset: "utf8mb4"
});

async function testDatabase() {
  try {
    const [rows] = await pool.query("SELECT 1 AS connected");
    console.log("✅ MySQL Connected Successfully");
    console.log(rows);
    return rows;
  } catch (error) {
    console.error("❌ MySQL Connection Failed");
    console.error(error.message);
    return null;
  }
}

module.exports = { pool, testDatabase };