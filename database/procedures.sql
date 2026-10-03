USE build8now;
DELIMITER $$

-- 1) Shipping: create profile with rules
DROP PROCEDURE IF EXISTS sp_create_shipping_profile_with_rules$$
CREATE PROCEDURE sp_create_shipping_profile_with_rules(
    IN p_name VARCHAR(120),
    IN p_description VARCHAR(500),
    IN p_combine_strategy VARCHAR(10),
    IN p_min_charge DECIMAL(12,2),
    IN p_max_charge DECIMAL(12,2),
    IN p_currency CHAR(3),
    IN p_created_by BIGINT UNSIGNED,
    IN p_rules JSON,
    OUT p_profile_id BIGINT UNSIGNED
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE rule_count INT;
    DECLARE v_basis VARCHAR(20);
    DECLARE v_calc_method VARCHAR(20);
    DECLARE v_range_min DECIMAL(14,4);
    DECLARE v_range_max DECIMAL(14,4);
    DECLARE v_rate DECIMAL(12,4);
    DECLARE v_label VARCHAR(120);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;
    INSERT INTO shipping_profiles
        (name, description, combine_strategy, min_charge, max_charge, currency, created_by)
    VALUES
        (p_name, p_description, p_combine_strategy, p_min_charge, p_max_charge, p_currency, p_created_by);

    SET p_profile_id = LAST_INSERT_ID();
    SET rule_count = JSON_LENGTH(p_rules);

    WHILE i < rule_count DO
        SET v_basis       = JSON_UNQUOTE(JSON_EXTRACT(p_rules, CONCAT('$[', i, '].basis')));
        SET v_calc_method = JSON_UNQUOTE(JSON_EXTRACT(p_rules, CONCAT('$[', i, '].calc_method')));
        SET v_rate        = JSON_EXTRACT(p_rules, CONCAT('$[', i, '].rate'));
        SET v_label       = JSON_UNQUOTE(JSON_EXTRACT(p_rules, CONCAT('$[', i, '].label')));

        IF JSON_EXTRACT(p_rules, CONCAT('$[', i, '].range_min')) IS NULL
           OR JSON_TYPE(JSON_EXTRACT(p_rules, CONCAT('$[', i, '].range_min'))) = 'NULL' THEN
            SET v_range_min = NULL;
        ELSE
            SET v_range_min = JSON_EXTRACT(p_rules, CONCAT('$[', i, '].range_min'));
        END IF;

        IF JSON_EXTRACT(p_rules, CONCAT('$[', i, '].range_max')) IS NULL
           OR JSON_TYPE(JSON_EXTRACT(p_rules, CONCAT('$[', i, '].range_max'))) = 'NULL' THEN
            SET v_range_max = NULL;
        ELSE
            SET v_range_max = JSON_EXTRACT(p_rules, CONCAT('$[', i, '].range_max'));
        END IF;

        INSERT INTO shipping_rules
            (profile_id, basis, calc_method, range_min, range_max, rate, label)
        VALUES
            (p_profile_id, v_basis, v_calc_method, v_range_min, v_range_max, v_rate, v_label);

        SET i = i + 1;
    END WHILE;
    COMMIT;
END$$

-- 2) Loyalty: award points (idempotent)
DROP PROCEDURE IF EXISTS sp_award_loyalty_points$$
CREATE PROCEDURE sp_award_loyalty_points(
    IN p_order_id BIGINT UNSIGNED,
    IN p_created_by BIGINT UNSIGNED,
    OUT p_total_awarded INT,
    OUT p_status VARCHAR(50)
)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_influencer_id BIGINT UNSIGNED;
    DECLARE v_item_id BIGINT UNSIGNED;
    DECLARE v_product_id BIGINT UNSIGNED;
    DECLARE v_category_id BIGINT UNSIGNED;
    DECLARE v_quantity INT;
    DECLARE v_line_total DECIMAL(12,2);
    DECLARE v_rule_id BIGINT UNSIGNED;
    DECLARE v_calc_type VARCHAR(30);
    DECLARE v_value DECIMAL(10,4);
    DECLARE v_points INT;
    DECLARE v_balance INT;
    DECLARE v_idem_key VARCHAR(100);

    DECLARE cur CURSOR FOR
        SELECT oi.id, oi.product_id, p.category_id, oi.quantity, oi.line_total
        FROM order_items oi
        JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id = p_order_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    SET p_total_awarded = 0;
    SET p_status = 'OK';
    START TRANSACTION;

    SELECT influencer_id INTO v_influencer_id
    FROM orders WHERE id = p_order_id FOR UPDATE;

    IF v_influencer_id IS NULL THEN
        SET p_status = 'NO_REFERRAL';
        COMMIT;
    ELSE
        OPEN cur;
        read_loop: LOOP
            FETCH cur INTO v_item_id, v_product_id, v_category_id, v_quantity, v_line_total;
            IF done = 1 THEN LEAVE read_loop; END IF;

            SET v_idem_key = CONCAT('ORDER_EARN:', p_order_id, ':', v_item_id);

            IF NOT EXISTS (SELECT 1 FROM loyalty_ledger WHERE idempotency_key = v_idem_key) THEN
                SET v_rule_id = NULL;
                SET v_calc_type = NULL;
                SET v_value = NULL;

                SELECT id, calc_type, value INTO v_rule_id, v_calc_type, v_value
                FROM loyalty_rules
                WHERE is_active = 1
                  AND min_order_value <= v_line_total
                  AND (
                      (scope = 'PRODUCT' AND product_id = v_product_id)
                   OR (scope = 'CATEGORY' AND category_id = v_category_id)
                   OR (scope = 'DEFAULT')
                  )
                ORDER BY FIELD(scope, 'PRODUCT', 'CATEGORY', 'DEFAULT'), min_order_value DESC
                LIMIT 1;

                IF v_rule_id IS NOT NULL THEN
                    IF v_calc_type = 'PERCENT_OF_VALUE' THEN
                        SET v_points = FLOOR(v_line_total * v_value / 100);
                    ELSE
                        SET v_points = FLOOR(v_value * v_quantity);
                    END IF;

                    IF v_points > 0 THEN
                        SELECT points_balance INTO v_balance
                        FROM influencers WHERE id = v_influencer_id FOR UPDATE;

                        SET v_balance = v_balance + v_points;

                        INSERT INTO loyalty_ledger
                            (influencer_id, entry_type, points, balance_after,
                             idempotency_key, order_id, order_item_id,
                             loyalty_rule_id, created_by)
                        VALUES
                            (v_influencer_id, 'EARN', v_points, v_balance,
                             v_idem_key, p_order_id, v_item_id,
                             v_rule_id, p_created_by);

                        UPDATE influencers SET points_balance = v_balance
                        WHERE id = v_influencer_id;

                        SET p_total_awarded = p_total_awarded + v_points;
                    END IF;
                END IF;
            END IF;
        END LOOP;
        CLOSE cur;
        COMMIT;
    END IF;
END$$

-- 3) Loyalty: reverse points (idempotent)
DROP PROCEDURE IF EXISTS sp_reverse_loyalty_points$$
CREATE PROCEDURE sp_reverse_loyalty_points(
    IN p_refund_item_id BIGINT UNSIGNED,
    IN p_created_by BIGINT UNSIGNED,
    OUT p_reversed INT,
    OUT p_status VARCHAR(50)
)
BEGIN
    DECLARE v_order_id BIGINT UNSIGNED;
    DECLARE v_order_item_id BIGINT UNSIGNED;
    DECLARE v_influencer_id BIGINT UNSIGNED;
    DECLARE v_orig_points INT;
    DECLARE v_orig_entry_id BIGINT UNSIGNED;
    DECLARE v_orig_qty INT;
    DECLARE v_refund_qty INT;
    DECLARE v_balance INT;
    DECLARE v_reverse INT;
    DECLARE v_idem_key VARCHAR(100);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    SET p_reversed = 0;
    SET p_status = 'OK';
    START TRANSACTION;

    SELECT orf.order_id, ori.order_item_id, ori.quantity
      INTO v_order_id, v_order_item_id, v_refund_qty
    FROM order_refund_items ori
    JOIN order_refunds orf ON orf.id = ori.refund_id
    WHERE ori.id = p_refund_item_id
    FOR UPDATE;

    IF v_order_id IS NULL THEN
        SET p_status = 'REFUND_ITEM_NOT_FOUND';
        COMMIT;
    ELSE
        SELECT influencer_id INTO v_influencer_id
        FROM orders WHERE id = v_order_id;

        IF v_influencer_id IS NULL THEN
            SET p_status = 'NO_REFERRAL';
            COMMIT;
        ELSE
            SET v_idem_key = CONCAT('REFUND_REV:', p_refund_item_id);

            IF EXISTS (SELECT 1 FROM loyalty_ledger WHERE idempotency_key = v_idem_key) THEN
                SET p_status = 'ALREADY_REVERSED';
                COMMIT;
            ELSE
                SELECT id, points INTO v_orig_entry_id, v_orig_points
                FROM loyalty_ledger
                WHERE idempotency_key = CONCAT('ORDER_EARN:', v_order_id, ':', v_order_item_id)
                LIMIT 1;

                IF v_orig_entry_id IS NULL THEN
                    SET p_status = 'NO_EARN_ENTRY';
                    COMMIT;
                ELSE
                    SELECT quantity INTO v_orig_qty
                    FROM order_items WHERE id = v_order_item_id;

                    SET v_reverse = -1 * FLOOR(v_orig_points * v_refund_qty / v_orig_qty);

                    SELECT points_balance INTO v_balance
                    FROM influencers WHERE id = v_influencer_id FOR UPDATE;

                    SET v_balance = v_balance + v_reverse;

                    INSERT INTO loyalty_ledger
                        (influencer_id, entry_type, points, balance_after,
                         idempotency_key, order_id, order_item_id, refund_item_id,
                         reverses_entry_id, created_by)
                    VALUES
                        (v_influencer_id, 'REVERSAL', v_reverse, v_balance,
                         v_idem_key, v_order_id, v_order_item_id, p_refund_item_id,
                         v_orig_entry_id, p_created_by);

                    UPDATE influencers SET points_balance = v_balance
                    WHERE id = v_influencer_id;

                    SET p_reversed = v_reverse;
                    COMMIT;
                END IF;
            END IF;
        END IF;
    END IF;
END$$

-- 4) Orders: create with items
DROP PROCEDURE IF EXISTS sp_create_order_with_items$$
CREATE PROCEDURE sp_create_order_with_items(
    IN p_order_number VARCHAR(30),
    IN p_customer_id BIGINT UNSIGNED,
    IN p_influencer_id BIGINT UNSIGNED,
    IN p_subtotal DECIMAL(12,2),
    IN p_shipping_total DECIMAL(12,2),
    IN p_currency CHAR(3),
    IN p_distance_km DECIMAL(10,2),
    IN p_items JSON,
    OUT p_order_id BIGINT UNSIGNED
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE cnt INT;
    DECLARE v_product_id BIGINT UNSIGNED;
    DECLARE v_qty INT;
    DECLARE v_unit_price DECIMAL(12,2);
    DECLARE v_line_total DECIMAL(12,2);
    DECLARE v_ship DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    INSERT INTO orders
        (order_number, customer_id, influencer_id, subtotal, shipping_total,
         grand_total, currency, distance_km)
    VALUES
        (p_order_number, p_customer_id, p_influencer_id, p_subtotal, p_shipping_total,
         p_subtotal + p_shipping_total, p_currency, p_distance_km);

    SET p_order_id = LAST_INSERT_ID();
    SET cnt = JSON_LENGTH(p_items);

    WHILE i < cnt DO
        SET v_product_id = JSON_EXTRACT(p_items, CONCAT('$[', i, '].product_id'));
        SET v_qty        = JSON_EXTRACT(p_items, CONCAT('$[', i, '].quantity'));
        SET v_unit_price = JSON_EXTRACT(p_items, CONCAT('$[', i, '].unit_price'));
        SET v_ship       = IFNULL(JSON_EXTRACT(p_items, CONCAT('$[', i, '].shipping_cost')), 0);
        SET v_line_total = v_unit_price * v_qty;

        INSERT INTO order_items
            (order_id, product_id, quantity, unit_price, line_total, shipping_cost)
        VALUES
            (p_order_id, v_product_id, v_qty, v_unit_price, v_line_total, v_ship);

        SET i = i + 1;
    END WHILE;

    COMMIT;
END$$

DELIMITER ;