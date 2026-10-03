const { pool } = require("../config/db");

function round2(n) {
  const num = Number(n);
  if (!Number.isFinite(num)) return 0;
  return Math.round((num + Number.EPSILON) * 100) / 100;
}

function toNum(v) {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function pickBasisValue(basis, input) {
  switch (basis) {
    case "WEIGHT": return toNum(input.weight_kg);
    case "QUANTITY": return toNum(input.quantity);
    case "PRICE": return toNum(input.price);
    case "DISTANCE": return toNum(input.distance_km);
    case "LENGTH": return toNum(input.length_cm);
    case "WIDTH": return toNum(input.width_cm);
    case "HEIGHT": return toNum(input.height_cm);
    case "VOLUME": {
      const L = toNum(input.length_cm);
      const W = toNum(input.width_cm);
      const H = toNum(input.height_cm);
      if (L && W && H) return (L * W * H) / 5000;
      return null;
    }
    case "AREA": {
      const L = toNum(input.length_cm);
      const W = toNum(input.width_cm);
      if (L && W) return L * W;
      return null;
    }
    default: return null;
  }
}

function calculateShippingCost(profile, rules, input) {
  if (!profile.is_active) {
    const e = new Error("Profile inactive");
    e.status = 400;
    throw e;
  }

  const contributions = [];

  for (const rule of rules) {
    const basisValue = rule.basis === "NONE" ? 0 : pickBasisValue(rule.basis, input);
    if (basisValue === null || basisValue < 0) continue;

    const rMin = rule.range_min != null ? toNum(rule.range_min) : null;
    const rMax = rule.range_max != null ? toNum(rule.range_max) : null;

    if (rMin !== null && basisValue < rMin) continue;
    if (rMax !== null && basisValue >= rMax) continue;

    const rateNum = toNum(rule.rate);
    if (rateNum === null) continue;

    const contribution = rule.calc_method === "FIXED"
      ? rateNum
      : rateNum * basisValue;

    contributions.push({
      rule_id: rule.id,
      label: rule.label,
      basis: rule.basis,
      value: basisValue,
      contribution: round2(contribution),
    });
  }

  if (!contributions.length) {
    const e = new Error("No rule matched");
    e.status = 400;
    throw e;
  }

  let total = profile.combine_strategy === "MAX"
    ? Math.max(...contributions.map((c) => c.contribution))
    : contributions.reduce((s, c) => s + c.contribution, 0);

  const minC = toNum(profile.min_charge);
  const maxC = toNum(profile.max_charge);

  if (minC !== null) total = Math.max(total, minC);
  if (maxC !== null) total = Math.min(total, maxC);

  return { total: round2(total), breakdown: contributions };
}

// ---------- Profile CRUD ----------

async function getProfileById(id) {
  const [profiles] = await pool.execute(
    `SELECT * FROM shipping_profiles WHERE id = ?`,
    [id]
  );
  if (!profiles.length) {
    const e = new Error("Profile not found");
    e.status = 404;
    throw e;
  }
  const [rules] = await pool.execute(
    `SELECT * FROM shipping_rules WHERE profile_id = ? ORDER BY id`,
    [id]
  );
  return { ...profiles[0], rules };
}

async function createProfile(input, createdBy) {
  const rulesJson = JSON.stringify(
    input.rules.map((r) => ({
      basis: r.basis,
      calc_method: r.calc_method,
      range_min: r.range_min ?? null,
      range_max: r.range_max ?? null,
      rate: Number(r.rate),
      label: r.label ?? null,
    }))
  );

  await pool.execute(
    `CALL sp_create_shipping_profile_with_rules(?, ?, ?, ?, ?, ?, ?, ?, @pid)`,
    [
      input.name,
      input.description ?? null,
      input.combine_strategy || "SUM",
      input.min_charge != null ? Number(input.min_charge) : null,
      input.max_charge != null ? Number(input.max_charge) : null,
      input.currency || "INR",
      createdBy,
      rulesJson,
    ]
  );

  const [[row]] = await pool.query(`SELECT @pid AS pid`);
  return getProfileById(row.pid);
}

async function listProfiles({ limit = 20, offset = 0, activeOnly = false }) {
  const where = activeOnly ? "WHERE is_active = 1" : "";
  const [items] = await pool.query(
    `SELECT * FROM shipping_profiles ${where} ORDER BY id DESC LIMIT ? OFFSET ?`,
    [Number(limit), Number(offset)]
  );
  const [[{ total }]] = await pool.query(
    `SELECT COUNT(*) AS total FROM shipping_profiles ${where}`
  );
  return { items, total };
}

async function deactivateProfile(id) {
  const [res] = await pool.execute(
    `UPDATE shipping_profiles SET is_active = 0 WHERE id = ?`,
    [id]
  );
  if (!res.affectedRows) {
    const e = new Error("Profile not found");
    e.status = 404;
    throw e;
  }
  return { id, is_active: false };
}

async function assignProfileToProduct(productId, profileId) {
  if (profileId) {
    const [p] = await pool.execute(
      `SELECT id, is_active FROM shipping_profiles WHERE id = ?`,
      [profileId]
    );
    if (!p.length) {
      const e = new Error("Profile not found");
      e.status = 404;
      throw e;
    }
    if (!p[0].is_active) {
      const e = new Error("Profile inactive");
      e.status = 400;
      throw e;
    }
  }
  const [res] = await pool.execute(
    `UPDATE products SET shipping_profile_id = ? WHERE id = ?`,
    [profileId, productId]
  );
  if (!res.affectedRows) {
    const e = new Error("Product not found");
    e.status = 404;
    throw e;
  }
  return { product_id: productId, shipping_profile_id: profileId };
}

async function calculateForProduct(input) {
  const productId = Number(input.product_id);
  const quantity = Number(input.quantity) || 1;
  const distanceKm = input.distance_km != null ? Number(input.distance_km) : null;

  const [prodRows] = await pool.execute(
    `SELECT id, name, price, weight_kg, length_cm, width_cm, height_cm,
            shipping_profile_id, currency, is_active
     FROM products WHERE id = ?`,
    [productId]
  );
  if (!prodRows.length) {
    const e = new Error("Product not found");
    e.status = 404;
    throw e;
  }
  const product = prodRows[0];

  if (!product.is_active) {
    const e = new Error("Product inactive");
    e.status = 400;
    throw e;
  }

  if (!product.shipping_profile_id) {
    const e = new Error("Product has no shipping profile");
    e.status = 400;
    throw e;
  }

  const profile = await getProfileById(product.shipping_profile_id);
  if (!profile.is_active) {
    const e = new Error("Profile inactive");
    e.status = 400;
    throw e;
  }

  const activeRules = profile.rules.filter((r) => r.is_active);
  const lineTotal = round2(toNum(product.price) * quantity);

  const calcInput = {
    weight_kg: product.weight_kg != null ? toNum(product.weight_kg) * quantity : null,
    quantity,
    price: lineTotal,
    distance_km: distanceKm,
    length_cm: toNum(product.length_cm),
    width_cm: toNum(product.width_cm),
    height_cm: toNum(product.height_cm),
  };

  const { total, breakdown } = calculateShippingCost(profile, activeRules, calcInput);

  return {
    product_id: product.id,
    product_name: product.name,
    profile_id: profile.id,
    profile_name: profile.name,
    currency: profile.currency,
    shipping_cost: total,
    breakdown,
    inputs: calcInput,
  };
}

module.exports = {
  createProfile,
  getProfileById,
  listProfiles,
  deactivateProfile,
  assignProfileToProduct,
  calculateForProduct,
  calculateShippingCost,
  pickBasisValue,
};