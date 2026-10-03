const svc = require("../services/orderService");

exports.create = async (req, res, next) => {
  try {
    const result = await svc.createOrder(req.user.id, req.body);
    res.status(201).json({ success: true, data: result });
  } catch (e) { next(e); }
};

exports.list = async (req, res, next) => {
  try {
    const isAdmin = req.user.role === "ADMIN";
    const { items, total } = await svc.listOrders({
      customerId: isAdmin ? null : req.user.id,
      limit: Number(req.query.limit) || 20,
      offset: Number(req.query.offset) || 0,
    });
    res.json({ success: true, data: items, pagination: { total } });
  } catch (e) { next(e); }
};

exports.getOne = async (req, res, next) => {
  try {
    const order = await svc.getOrderById(Number(req.params.id));
    if (req.user.role !== "ADMIN" && order.customer_id !== req.user.id) {
      return res.status(403).json({ success: false, error: "Forbidden" });
    }
    res.json({ success: true, data: order });
  } catch (e) { next(e); }
};

exports.cancel = async (req, res, next) => {
  try {
    const order = await svc.cancelOrder(
      Number(req.params.id),
      req.user.id,
      req.user.role === "ADMIN"
    );
    res.json({ success: true, data: order });
  } catch (e) { next(e); }
};