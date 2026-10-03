const svc = require("../services/loyaltyService");

exports.balance = async (req, res, next) => {
  try {
    const data = await svc.getBalance(req.user.id);
    res.json({ success: true, data });
  } catch (e) { next(e); }
};

exports.ledger = async (req, res, next) => {
  try {
    const { items, total } = await svc.getLedger(req.user.id, req.query);
    res.json({
      success: true,
      data: items,
      pagination: { total, limit: Number(req.query.limit) || 20, offset: Number(req.query.offset) || 0 },
    });
  } catch (e) { next(e); }
};

exports.referredCustomers = async (req, res, next) => {
  try {
    const data = await svc.getReferredCustomers(req.user.id);
    res.json({ success: true, data });
  } catch (e) { next(e); }
};