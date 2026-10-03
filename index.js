require("dotenv").config();
const app = require("./src/app");
const { testDatabase } = require("./src/config/db");

const port = Number(process.env.PORT || 5000);

(async () => {
  const db = await testDatabase();
  if (!db) {
    console.error("❌ Cannot start server without DB");
    process.exit(1);
  }
  app.listen(port, () => {
    console.log(`🚀 Server running on port ${port}`);
  });
})();