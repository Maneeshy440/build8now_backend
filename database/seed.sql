USE build8now;

-- Passwords below are bcrypt hashes of "Password123!" (12 rounds)
-- Copy the hash from your existing users table if you already have one
SET @pwd := (SELECT password_hash FROM users LIMIT 1);

-- Insert users (only if not exists)
INSERT IGNORE INTO users (email, password_hash, full_name, role)
VALUES
('admin@b8n.com', @pwd, 'Admin User', 'ADMIN'),
('customer@b8n.com', @pwd, 'Test Customer', 'CUSTOMER'),
('architect@b8n.com', @pwd, 'Test Architect', 'INFLUENCER');

-- Category
INSERT IGNORE INTO categories (id, name, slug) VALUES (1, 'Cement', 'cement');

-- Shipping profile
INSERT INTO shipping_profiles
    (name, combine_strategy, min_charge, max_charge, currency, created_by)
SELECT 'Standard Shipping', 'SUM', 50.00, 5000.00, 'IN