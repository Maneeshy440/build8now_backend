const { pool } = require("../config/db");

async function awardPointsForOrder(orderId, createdBy) {
  // Call stored procedure
  await pool.execute(
    `CALL sp_award_loyalty_points(?, ?, @total, @status)`,
    [orderId, createdBy]
  );
  const [[row]] = await pool.query(`SELECT @total AS total, @status AS status`);

  return {
    total_awarded: Number(row.total) || 0,
    status: row.status,
  };
}

async function reversePointsForRefund(refundItemId, createdBy) {
  await pool.execute(
    `CALL sp_reverse_loyalty_points(?, ?, @reversed, @status)`,
    [refundItemId, createdBy]
  );
  const [[row]] = await pool.query(`SELECT @reversed AS reversed, @status AS status`);

  return {
    reversed: Number(row.reversed) || 0,
    status: row.status,
  };
}

async function getInfluencerByUserId(userId) {
  const [rows] = await pool.execute(
    `SELECT id, user_id, influencer_type, referral_code, company_name, points_balance, is_active
     FROM influencers WHERE user_id = ? LIMIT 1`,
    [userId]
  );
  if (!rows.length) {
    const e = new Error("Influencer profile not found");
    e.status = 404;
    throw e;
  }
  return rows[0];
}

async function getBalance(userId) {
  const inf = await getInfluencerByUserId(userId);
  return {
    influencer_id: inf.id,
    referral_code: inf.referral_code,
    points_balance: inf.points_balance,
  };
}

async function getLedger(userId, { limit = 20, offset = 0 } = {}) {
  const inf = await getInfluencerByUserId(userId);

  const [items] = await pool.query(
    `SELECT id, entry_type, points, balance_after, idempotency_key,
            order_id, order_item_id, refund_item_id, description, created_at
     FROM loyalty_ledger
     WHERE influencer_id = ?
     ORDER BY id DESC
     LIMIT ? OFFSET ?`,
    [inf.id, Number(limit), Number(offset)]
  );

  const [[{ total }]] = await pool.query(
    `SELECT COUNT(*) AS total FROM loyalty_ledger WHERE influencer_id = ?`,
    [inf.id]
  );

  return { items, total };
}

async function getReferredCustomers(userId) {
  const inf = await getInfluencerByUserId(userId);

  const [rows] = await pool.query(
    `SELECT r.id AS referral_id, r.created_at,
            u.id AS customer_id, u.email, u.full_name
     FROM referrals r
     JOIN users u ON u.id = r.customer_id
     WHERE r.influencer_id = ?
     ORDER BY r.created_at DESC`,
    [inf.id]
  );

  return rows;
}

module.exports = {
  awardPointsForOrder,
  reversePointsForRefund,
  getInfluencerByUserId,
  getBalance,
  getLedger,
  getReferredCustomers,
};