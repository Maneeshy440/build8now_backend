-- =====================================================================
-- Build8Now - Complete Database Schema
-- MySQL 8.0.16+ / InnoDB / utf8mb4
-- =====================================================================

DROP DATABASE IF EXISTS build8now;
CREATE DATABASE build8now
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE build8now;

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- =====================================================================
-- 1. USERS & AUTH
-- =====================================================================
CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NULL,
    role ENUM('ADMIN','CUSTOMER','INFLUENCER') NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_users_email UNIQUE (email)
) ENGINE=InnoDB;

CREATE INDEX idx_users_role ON users (role);

CREATE TABLE refresh_tokens (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash CHAR(64) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_refresh_user ON refresh_tokens (user_id);

-- =====================================================================
-- 2. CATALOGUE
-- =====================================================================
CREATE TABLE categories (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    parent_id BIGINT UNSIGNED NULL,
    name VARCHAR(120) NOT NULL,
    slug VARCHAR(140) NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_categories_slug UNIQUE (slug),
    CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id)
        REFERENCES categories(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- =====================================================================
-- 3. SHIPPING PROFILES & RULES
-- =====================================================================
CREATE TABLE shipping_profiles (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    description VARCHAR(500) NULL,
    combine_strategy ENUM('SUM','MAX') NOT NULL DEFAULT 'SUM',
    min_charge DECIMAL(12,2) NULL,
    max_charge DECIMAL(12,2) NULL,
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_shipping_profiles_name UNIQUE (name),
    CONSTRAINT chk_sp_min CHECK (min_charge IS NULL OR min_charge >= 0),
    CONSTRAINT chk_sp_max CHECK (max_charge IS NULL OR max_charge >= 0),
    CONSTRAINT chk_sp_range CHECK (
        min_charge IS NULL OR max_charge IS NULL OR max_charge >= min_charge
    ),
    CONSTRAINT fk_sp_created_by FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE INDEX idx_sp_active ON shipping_profiles (is_active);

CREATE TABLE shipping_rules (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    profile_id BIGINT UNSIGNED NOT NULL,
    basis ENUM('NONE','WEIGHT','QUANTITY','PRICE','DISTANCE',
               'LENGTH','WIDTH','HEIGHT','VOLUME','AREA') NOT NULL,
    calc_method ENUM('FIXED','PER_UNIT') NOT NULL,
    range_min DECIMAL(14,4) NULL,
    range_max DECIMAL(14,4) NULL,
    rate DECIMAL(12,4) NOT NULL,
    label VARCHAR(120) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT fk_sr_profile FOREIGN KEY (profile_id)
        REFERENCES shipping_profiles(id) ON DELETE CASCADE,
    CONSTRAINT chk_sr_rate CHECK (rate >= 0),
    CONSTRAINT chk_sr_min CHECK (range_min IS NULL OR range_min >= 0),
    CONSTRAINT chk_sr_max_gt CHECK (
        range_max IS NULL OR range_min IS NULL OR range_max > range_min
    ),
    CONSTRAINT chk_sr_flat CHECK (
        basis <> 'NONE' OR (
            calc_method = 'FIXED' AND range_min IS NULL AND range_max IS NULL
        )
    ),
    CONSTRAINT uq_sr_slab_start UNIQUE (profile_id, basis, range_min)
) ENGINE=InnoDB;

-- =====================================================================
-- 4. PRODUCTS
-- =====================================================================
CREATE TABLE products (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(64) NOT NULL,
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(220) NOT NULL,
    description TEXT NULL,
    brand VARCHAR(120) NULL,
    category_id BIGINT UNSIGNED NOT NULL,
    shipping_profile_id BIGINT UNSIGNED NULL,
    price DECIMAL(12,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    weight_kg DECIMAL(10,3) NULL,
    length_cm DECIMAL(10,2) NULL,
    width_cm DECIMAL(10,2) NULL,
    height_cm DECIMAL(10,2) NULL,
    availability ENUM('IN_STOCK','OUT_OF_STOCK','PREORDER')
        NOT NULL DEFAULT 'IN_STOCK',
    image_url VARCHAR(500) NULL,
    image_alt VARCHAR(200) NULL,
    meta_title VARCHAR(70) NULL,
    meta_description VARCHAR(160) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_products_sku UNIQUE (sku),
    CONSTRAINT uq_products_slug UNIQUE (slug),
    CONSTRAINT fk_products_category FOREIGN KEY (category_id)
        REFERENCES categories(id),
    CONSTRAINT fk_products_profile FOREIGN KEY (shipping_profile_id)
        REFERENCES shipping_profiles(id),
    CONSTRAINT chk_products_price CHECK (price >= 0),
    CONSTRAINT chk_products_weight CHECK (weight_kg IS NULL OR weight_kg > 0)
) ENGINE=InnoDB;

CREATE INDEX idx_products_category ON products (category_id);
CREATE INDEX idx_products_profile ON products (shipping_profile_id);

CREATE TABLE product_slug_redirects (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    old_slug VARCHAR(220) NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_redirect_old_slug UNIQUE (old_slug),
    CONSTRAINT fk_redirect_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
-- 5. INFLUENCERS & REFERRALS
-- =====================================================================
CREATE TABLE influencers (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    influencer_type ENUM('ARCHITECT','CONTRACTOR','INTERIOR_DESIGNER','BUILDER','OTHER')
        NOT NULL,
    referral_code VARCHAR(20) NOT NULL,
    company_name VARCHAR(150) NULL,
    points_balance INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_influencers_user UNIQUE (user_id),
    CONSTRAINT uq_influencers_code UNIQUE (referral_code),
    CONSTRAINT fk_influencers_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE INDEX idx_influencers_type ON influencers (influencer_type);

CREATE TABLE referrals (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED NOT NULL,
    influencer_id BIGINT UNSIGNED NOT NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_referrals_customer UNIQUE (customer_id),
    CONSTRAINT fk_referrals_customer FOREIGN KEY (customer_id) REFERENCES users(id),
    CONSTRAINT fk_referrals_influencer FOREIGN KEY (influencer_id) REFERENCES influencers(id),
    CONSTRAINT fk_referrals_created_by FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE INDEX idx_referrals_influencer ON referrals (influencer_id, created_at);

-- =====================================================================
-- 6. ORDERS
-- =====================================================================
CREATE TABLE orders (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_number VARCHAR(30) NOT NULL,
    customer_id BIGINT UNSIGNED NOT NULL,
    influencer_id BIGINT UNSIGNED NULL,
    status ENUM('PLACED','CONFIRMED','DELIVERED','CANCELLED','PARTIALLY_REFUNDED','REFUNDED')
        NOT NULL DEFAULT 'PLACED',
    subtotal DECIMAL(12,2) NOT NULL,
    shipping_total DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    grand_total DECIMAL(12,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    distance_km DECIMAL(10,2) NULL,
    cancelled_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_orders_number UNIQUE (order_number),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES users(id),
    CONSTRAINT fk_orders_influencer FOREIGN KEY (influencer_id) REFERENCES influencers(id),
    CONSTRAINT chk_orders_subtotal CHECK (subtotal >= 0),
    CONSTRAINT chk_orders_shipping CHECK (shipping_total >= 0),
    CONSTRAINT chk_orders_total CHECK (grand_total = subtotal + shipping_total),
    CONSTRAINT chk_orders_cancel CHECK (
        (status = 'CANCELLED') = (cancelled_at IS NOT NULL)
    )
) ENGINE=InnoDB;

CREATE INDEX idx_orders_customer ON orders (customer_id, created_at);
CREATE INDEX idx_orders_influencer ON orders (influencer_id, created_at);
CREATE INDEX idx_orders_status ON orders (status);

CREATE TABLE order_items (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    line_total DECIMAL(12,2) NOT NULL,
    shipping_cost DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    refunded_quantity INT UNSIGNED NOT NULL DEFAULT 0,
    CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT uq_oi_order_product UNIQUE (order_id, product_id),
    CONSTRAINT chk_oi_qty CHECK (quantity > 0),
    CONSTRAINT chk_oi_price CHECK (unit_price >= 0),
    CONSTRAINT chk_oi_total CHECK (line_total = unit_price * quantity),
    CONSTRAINT chk_oi_ship CHECK (shipping_cost >= 0),
    CONSTRAINT chk_oi_refunded CHECK (refunded_quantity <= quantity)
) ENGINE=InnoDB;

CREATE INDEX idx_oi_product ON order_items (product_id);

CREATE TABLE order_refunds (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    refund_reference VARCHAR(64) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    reason VARCHAR(255) NULL,
    created_by BIGINT UNSIGNED NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_refunds_reference UNIQUE (refund_reference),
    CONSTRAINT fk_refunds_order FOREIGN KEY (order_id) REFERENCES orders(id),
    CONSTRAINT fk_refunds_created_by FOREIGN KEY (created_by) REFERENCES users(id),
    CONSTRAINT chk_refunds_amount CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE INDEX idx_refunds_order ON order_refunds (order_id);

CREATE TABLE order_refund_items (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    refund_id BIGINT UNSIGNED NOT NULL,
    order_item_id BIGINT UNSIGNED NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    CONSTRAINT fk_ri_refund FOREIGN KEY (refund_id) REFERENCES order_refunds(id),
    CONSTRAINT fk_ri_item FOREIGN KEY (order_item_id) REFERENCES order_items(id),
    CONSTRAINT uq_ri_refund_item UNIQUE (refund_id, order_item_id),
    CONSTRAINT chk_ri_qty CHECK (quantity > 0),
    CONSTRAINT chk_ri_amount CHECK (amount >= 0)
) ENGINE=InnoDB;

CREATE INDEX idx_ri_order_item ON order_refund_items (order_item_id);

-- =====================================================================
-- 7. LOYALTY RULES
-- =====================================================================
CREATE TABLE loyalty_rules (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    scope ENUM('PRODUCT','CATEGORY','DEFAULT') NOT NULL,
    product_id BIGINT UNSIGNED NULL,
    category_id BIGINT UNSIGNED NULL,
    calc_type ENUM('PERCENT_OF_VALUE','POINTS_PER_UNIT') NOT NULL,
    value DECIMAL(10,4) NOT NULL,
    min_order_value DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),
    target_key BIGINT UNSIGNED AS (COALESCE(product_id, category_id, 0)) STORED,
    active_key TINYINT AS (IF(is_active, 1, NULL)) STORED,
    CONSTRAINT fk_lr_product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT fk_lr_category FOREIGN KEY (category_id) REFERENCES categories(id),
    CONSTRAINT fk_lr_created_by FOREIGN KEY (created_by) REFERENCES users(id),
    CONSTRAINT chk_lr_value CHECK (value > 0),
    CONSTRAINT chk_lr_pct CHECK (
        calc_type <> 'PERCENT_OF_VALUE' OR value <= 100
    ),
    CONSTRAINT chk_lr_min_order CHECK (min_order_value >= 0),
    CONSTRAINT chk_lr_scope CHECK (
        (scope = 'PRODUCT' AND product_id IS NOT NULL AND category_id IS NULL)
     OR (scope = 'CATEGORY' AND category_id IS NOT NULL AND product_id IS NULL)
     OR (scope = 'DEFAULT' AND product_id IS NULL AND category_id IS NULL)
    ),
    CONSTRAINT uq_lr_active UNIQUE (scope, target_key, min_order_value, active_key)
) ENGINE=InnoDB;

CREATE INDEX idx_lr_product ON loyalty_rules (product_id, is_active);
CREATE INDEX idx_lr_category ON loyalty_rules (category_id, is_active);

-- =====================================================================
-- 8. LOYALTY LEDGER
-- =====================================================================
CREATE TABLE loyalty_ledger (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    influencer_id BIGINT UNSIGNED NOT NULL,
    entry_type ENUM('EARN','REVERSAL','REDEEM','ADJUSTMENT') NOT NULL,
    points INT NOT NULL,
    balance_after INT NOT NULL,
    idempotency_key VARCHAR(100) NOT NULL,
    order_id BIGINT UNSIGNED NULL,
    order_item_id BIGINT UNSIGNED NULL,
    refund_item_id BIGINT UNSIGNED NULL,
    loyalty_rule_id BIGINT UNSIGNED NULL,
    reverses_entry_id BIGINT UNSIGNED NULL,
    description VARCHAR(255) NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT uq_ledger_idempotency UNIQUE (idempotency_key),
    CONSTRAINT fk_ledger_influencer FOREIGN KEY (influencer_id) REFERENCES influencers(id),
    CONSTRAINT fk_ledger_order FOREIGN KEY (order_id) REFERENCES orders(id),
    CONSTRAINT fk_ledger_order_item FOREIGN KEY (order_item_id) REFERENCES order_items(id),
    CONSTRAINT fk_ledger_refund FOREIGN KEY (refund_item_id) REFERENCES order_refund_items(id),
    CONSTRAINT fk_ledger_rule FOREIGN KEY (loyalty_rule_id) REFERENCES loyalty_rules(id),
    CONSTRAINT fk_ledger_reverses FOREIGN KEY (reverses_entry_id) REFERENCES loyalty_ledger(id),
    CONSTRAINT fk_ledger_created_by FOREIGN KEY (created_by) REFERENCES users(id),
    CONSTRAINT chk_ledger_nonzero CHECK (points <> 0),
    CONSTRAINT chk_ledger_sign CHECK (
        (entry_type = 'EARN' AND points > 0)
     OR (entry_type = 'REVERSAL' AND points < 0)
     OR (entry_type = 'REDEEM' AND points < 0)
     OR (entry_type = 'ADJUSTMENT')
    ),
    CONSTRAINT chk_ledger_earn_ref CHECK (
        entry_type <> 'EARN' OR order_item_id IS NOT NULL
    ),
    CONSTRAINT chk_ledger_reversal_ref CHECK (
        entry_type <> 'REVERSAL' OR reverses_entry_id IS NOT NULL
    )
) ENGINE=InnoDB;

CREATE INDEX idx_ledger_influencer ON loyalty_ledger (influencer_id, created_at, id);
CREATE INDEX idx_ledger_order ON loyalty_ledger (order_id);
CREATE INDEX idx_ledger_reverses ON loyalty_ledger (reverses_entry_id);

-- =====================================================================
-- Append-only triggers
-- =====================================================================
DELIMITER $$
CREATE TRIGGER trg_ledger_no_update
BEFORE UPDATE ON loyalty_ledger
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'loyalty_ledger is append-only';
END$$

CREATE TRIGGER trg_ledger_no_delete
BEFORE DELETE ON loyalty_ledger
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'loyalty_ledger is append-only';
END$$
DELIMITER ;

-- =====================================================================
-- 9. Reconciliation view
-- =====================================================================
CREATE VIEW v_influencer_balance_mismatch AS
SELECT
    i.id AS influencer_id,
    i.points_balance AS cached_balance,
    COALESCE(SUM(l.points), 0) AS ledger_balance
FROM influencers i
LEFT JOIN loyalty_ledger l ON l.influencer_id = i.id
GROUP BY i.id, i.points_balance
HAVING cached_balance <> ledger_balance;