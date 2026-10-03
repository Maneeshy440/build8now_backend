const svc = require("../services/shippingService");

exports.create = async (req, res, next) => {
  try {
    const data = await svc.createProfile(req.body, req.user.id);
    res.status(201).json({ success: true, data });
  } catch (e) { next(e); }
};

exports.list = async (req, res, next) => {
  try {
    const { items, total } = await svc.listProfiles(req.query);
    res.json({ success: true, data: items, pagination: { total } });
  } catch (e) { next(e); }
};

exports.getOne = async (req, res, next) => {
  try {
    const data = await svc.getProfileById(Number(req.params.id));
    res.json({ success: true, data });
  } catch (e) { next(e); }
};

exports.deactivate = async (req, res, next) => {
  try {
    const data = await svc.deactivateProfile(Number(req.params.id));
    res.json({ success: true, data });
  } catch (e) { next(e); }
};

exports.assign = async (req, res, next) => {
  try {
    const data = await svc.assignProfileToProduct(
      Number(req.params.productId),
      req.body.profile_id
    );
    res.json({ success: true, data });
  } catch (e) { next(e); }
};

exports.calculate = async (req, res, next) => {
  try {
    const data = await svc.calculateForProduct(req.body);
    res.json({ success: true, data });
  } catch (e) { next(e); }
};