function authorize(...roles) {
  return (req, res, next) => {
    const user = req.user;

    if (!user) {
      return res.status(401).json({ success: false, error: "Authentication required." });
    }

    if (!roles.includes(user.role)) {
      return res.status(403).json({ success: false, error: "You do not have permission to access this resource." });
    }

    return next();
  };
}

function authorizeObjectAccess({ resourceUserId, allowAdmin = true } = {}) {
  return (req, res, next) => {
    const user = req.user;

    if (!user) {
      return res.status(401).json({ success: false, error: "Authentication required." });
    }

    const targetId = Number(resourceUserId ?? req.params.userId ?? req.params.id ?? req.body.user_id ?? req.query.user_id);

    if (allowAdmin && user.role === "admin") {
      return next();
    }

    if (user.id === targetId) {
      return next();
    }

    return res.status(403).json({ success: false, error: "Access denied: you can only access your own records." });
  };
}

module.exports = { authorize, authorizeObjectAccess };
