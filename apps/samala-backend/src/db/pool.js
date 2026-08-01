const { Pool } = require("pg");

const pool = new Pool({
  host: process.env.DB_HOST || "samala-database",
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER || "samala_user",
  password: process.env.DB_PASSWORD || "samala_pass",
  database: process.env.DB_NAME || "samala_db",
});

pool.on("error", (err) => console.error("Unexpected DB error", err));

module.exports = pool;
