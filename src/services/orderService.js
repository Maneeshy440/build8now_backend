const { pool } = require("../config/db");
const loyalty = require("./loyaltyService");

function round2(n) {
  return Math.round((Number(n) + Number.EPSILON) * 100) / 100;
}

function genOrderNumber() {
  const ts = Date.now().toString(36).toUpperCase();
  const rand = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `ORD-${ts}-${rand}`;
}

async function createOrder(customerId, { items, distance_km = null }) {
  if (!Array.isArray(items) || !items.length) {
    const e = new Error("items array required");
    e.status = 400;
    throw e;
  }

  // 1. Fetch products + their shipping profiles
  const productIds = items.map((i) => Number(i.product_id));
  const [products] = await pool.query(
    `SELECT id, name, price, weight_kg, length_cm, width_cm, height_cm,
            shipping_profile_id, currency, is_active
     FROM products WHERE id IN (?)`,
    [productIds]
  );

  if (products.length !== productIds.length) {
    const e = new Error("One or more products not found");
    e.status = 404;
    throw e;
  }

  // 2. Compute per-line: unit_price, shipping_cost, line_total
  const shippingSvc = require("./shippingService");
  const lineItems = [];
  let subtotal = 0;
  let shippingTotal = 0;

  for (const item of items) {
    const product = products.find((p) => p.id === Number(item.product_id));
    if (!product.is_active) {
      const e = new Error(`Product ${product.name} is inactive`);
      e.status = 400;
      throw e;
    }
    const qty = Number(item.quantity);
    if (!qty || qty < 1) {
      const e = new Error("quantity must be >= 1");
      e.status = 400;
      throw e;
    }

    const unitPrice = Number(product.price);
    const lineTotal = round2(unitPrice * qty);

    let lineShipping = 0;
    if (product.shipping_profile_id) {
      try {
        const calc = await shippingSvc.calculateForProduct({
          product_id: product.id,
          quantity: qty,
          distance_km,
        });
        lineShipping = calc.shipping_cost;
      } catch (err) {
        // if no rule matched, treat as zero shipping (or rethrow)
        lineShipping = 0;
      }
    }

    subtotal += lineTotal;
    shippingTotal += lineShipping;

    lineItems.push({
      product_id: product.id,
      quantity: qty,
      unit_price: unitPrice,
      line_total: lineTotal,
      shipping_cost: lineShipping,
    });
  }

  subtotal = round2(subtotal);
  shippingTotal = round2(shippingTotal);

  // 3. Look up referral influencer (if any)
  const [refRows] = await pool.query(
    `SELECT influencer_id FROM referrals WHERE customer_id = ? LIMIT 1`,
    [customerId]
  );
  const influencerId = refRows.length ? refRows[0].influencer_id : null;

  // 4. Call procedure to insert order + items
  const orderNumber = genOrderNumber();
  const currency = products[0].currency || "INR";
  const itemsJson = JSON.stringify(lineItems);

  await pool.execute(
    `CALL sp_create_order_with_items(?, ?, ?, ?, ?, ?, ?, ?, @oid)`,
    [
      orderNumber,
      customerId,
      influencerId,
      subtotal,
      shippingTotal,
      currency,
      distance_km,
      itemsJson,
    ]
  );
  const [[{ "@oid": orderId }]] = await pool.query(`SELECT @oid`);

  // 5. Award points (idempotent via procedure)
  let award = { total_awarded: 0, status: "SKIPPED" };
  if (influencerId) {
    try {
      award = await loyalty.awardPointsForOrder(orderId, customerId);
    } catch (err) {
      console.error("Award error:", err.message);
      award = { total_awarded: 0, status: "ERROR" };
    }
  }

  // 6. Return full order
  const order = await getOrderById(orderId);
  return { order, award };
}

async function getOrderById(orderId) {
  const [orders] = await pool.execute(
    `SELECT * FROM orders WHERE id = ?`,
    [orderId]
  );
  if (!orders.length) {
    const e = new Error("Order not found");
    e.status = 404;
    throw e;
  }
  const [items] = await pool.execute(
    `SELECT * FROM order_items WHERE order_id = ?`,
    [orderId]
  );
  return { ...orders[0], items };
}

async function listOrders({ customerId = null, limit = 20, offset = 0 }) {
  const where = customerId ? "WHERE customer_id = ?" : "";
  const params = customerId ? [customerId, Number(limit), Number(offset)] : [Number(limit), Number(offset)];

  const [items] = await pool.query(
    `SELECT * FROM orders ${where} ORDER BY id DESC LIMIT ? OFFSET ?`,
    params
  );

  const [[{ total }]] = await pool.query(
    `SELECT COUNT(*) AS total FROM orders ${where}`,
    customerId ? [customerId] : []
  );

  return { items, total };
}

async function cancelOrder(orderId, actorUserId, isAdmin) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [rows] = await conn.execute(
      `SELECT * FROM orders WHERE id = ? FOR UPDATE`,
      [orderId]
    );
    if (!rows.length) {
      const e = new Error("Order not found");
      e.status = 404;
      throw e;
    }
    const order = rows[0];

    if (!isAdmin && order.customer_id !== actorUserId) {
      const e = new Error("Forbidden");
      e.status = 403;
      throw e;
    }

    if (order.status === "CANCELLED") {
      const e = new Error("Already cancelled");
      e.status = 400;
      throw e;
    }

    // Update status
    await conn.execute(
      `UPDATE orders SET status = 'CANCELLED', cancelled_at = NOW(3) WHERE id = ?`,
      [orderId]
    );

    await conn.commit();

    // Reverse loyalty points (outside txn — procedure has own txn)
    let reversal = { reversed: 0, status: "SKIPPED" };
    try {
      // Find order items and reverse each
      const [items] = await pool.execute(
        `SELECT id, quantity FROM order_items WHERE order_id = ?`,
        [orderId]
      );
      // For cancel, we insert a refund row of full amount then reverse each item
      // Simplify: directly create refund rows
      const [inf] = await pool.query(
        `SELECT influencer_id FROM referrals r
         JOIN orders o ON o.customer_id = r.customer_id
         WHERE o.id = ? LIMIT 1`,
        [orderId]
      );
      if (inf.length && inf[0].influencer_id) {
        // Create refund record for full cancel
        const [rres] = await pool.execute(
          `INSERT INTO order_refunds (order_id, refund_reference, amount, reason, created_by)
           VALUES (?, ?, ?, ?, ?)`,
          [orderId, `CANCEL-${orderId}-${Date.now()}`, order.grand_total, "Order cancelled", actorUserId]
        );
        const refundId = rres.insertId;

        for (const oi of items) {
          const [rri] = await pool.execute(
            `INSERT INTO order_refund_items (refund_id, order_item_id, quantity, amount)
             VALUES (?, ?, ?, ?)`,
            [refundId, oi.id, oi.quantity, 0]
          );
          try {
            await loyalty.reversePointsForRefund(rri.insertId, actorUserId);
          } catch (e) {
            console.error("Reverse error:", e.message);
          }
        }
      }
    } catch (e) {
      console.error("Cancel reversal error:", e.message);
    }

    return getOrderById(orderId);
  } catch (e) {
    await conn.rollback();
    throw e;
  } finally {
    conn.release();
  }
}

module.exports = {
  createOrder,
  getOrderById,
  listOrders,
  cancelOrder,
};