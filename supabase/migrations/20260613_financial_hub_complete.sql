-- =============================================================
-- RodMae App - Financial Hub Complete Migration v8 (FINAL)
-- Fix: Use ::TEXT cast on BOTH sides of all comparisons so
--      it works regardless of UUID or VARCHAR column types.
-- =============================================================

-- ---------------------------------------------------------------
-- 1. WALLETS (table already exists — patch missing columns only)
-- ---------------------------------------------------------------
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS name          VARCHAR;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS wallet_type   VARCHAR NOT NULL DEFAULT 'e_money';
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS logo_url      VARCHAR;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS balance       NUMERIC(12,2) NOT NULL DEFAULT 0.00;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS currency      VARCHAR(3) NOT NULL DEFAULT 'PHP';
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS is_shared     BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS color_hex     VARCHAR(7);
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS updated_at    TIMESTAMPTZ NOT NULL DEFAULT now();

-- ---------------------------------------------------------------
-- 2. TRANSACTIONS - patch new columns
-- ---------------------------------------------------------------
ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS is_split       BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS split_with_id  VARCHAR,
    ADD COLUMN IF NOT EXISTS receipt_url    VARCHAR;

-- ---------------------------------------------------------------
-- 3. BILL SPLITTING
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_splits (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    user_id        VARCHAR NOT NULL,
    amount_owed    NUMERIC(12,2) NOT NULL,
    is_settled     BOOLEAN NOT NULL DEFAULT FALSE,
    settled_at     TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE transaction_splits ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_splits_transaction ON transaction_splits(transaction_id);
CREATE INDEX IF NOT EXISTS idx_splits_user        ON transaction_splits(user_id);

-- ---------------------------------------------------------------
-- 4. INCOME ENTRIES
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS income_entries (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      VARCHAR NOT NULL,
    household_id VARCHAR NOT NULL,
    source_name  VARCHAR NOT NULL,
    amount       NUMERIC(12,2) NOT NULL,
    type         VARCHAR NOT NULL DEFAULT 'one-time',
    frequency    VARCHAR NOT NULL DEFAULT 'monthly',
    date         TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE income_entries ADD COLUMN IF NOT EXISTS frequency VARCHAR NOT NULL DEFAULT 'monthly';
ALTER TABLE income_entries ADD COLUMN IF NOT EXISTS notes     TEXT;
CREATE INDEX IF NOT EXISTS idx_income_household ON income_entries(household_id);

-- ---------------------------------------------------------------
-- 5. NET WORTH SNAPSHOTS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS net_worth_snapshots (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id      VARCHAR NOT NULL,
    total_assets      NUMERIC(12,2) NOT NULL,
    total_liabilities NUMERIC(12,2) NOT NULL,
    captured_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_networth_household ON net_worth_snapshots(household_id, captured_at DESC);

-- ---------------------------------------------------------------
-- 6. ASSETS AND LIABILITIES
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS assets_liabilities (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  VARCHAR NOT NULL,
    type          VARCHAR NOT NULL,
    name          VARCHAR NOT NULL,
    current_value NUMERIC(12,2) NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- 7. MONEY CHECK-INS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS checkins (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id VARCHAR NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    notes        TEXT,
    mood_score   INT CHECK (mood_score >= 1 AND mood_score <= 5),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE checkins ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE checkins ADD COLUMN IF NOT EXISTS notes        TEXT;
ALTER TABLE checkins ADD COLUMN IF NOT EXISTS mood_score   INT;

-- ---------------------------------------------------------------
-- 8. ALERTS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS alerts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id VARCHAR NOT NULL,
    user_id      VARCHAR,
    type         VARCHAR NOT NULL,
    message      TEXT NOT NULL,
    is_read      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS user_id VARCHAR;
CREATE INDEX IF NOT EXISTS idx_alerts_household ON alerts(household_id, is_read, created_at DESC);

-- ---------------------------------------------------------------
-- 9. LIFE EVENT PLANNER
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS life_events (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   VARCHAR NOT NULL,
    type           VARCHAR NOT NULL,
    name           VARCHAR NOT NULL,
    target_date    TIMESTAMPTZ,
    estimated_cost NUMERIC(12,2) NOT NULL,
    current_saved  NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE life_events ADD COLUMN IF NOT EXISTS target_date   TIMESTAMPTZ;
ALTER TABLE life_events ADD COLUMN IF NOT EXISTS current_saved NUMERIC(12,2) NOT NULL DEFAULT 0.00;

CREATE TABLE IF NOT EXISTS event_cost_items (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id         UUID REFERENCES life_events(id) ON DELETE CASCADE,
    item_name        VARCHAR NOT NULL,
    estimated_amount NUMERIC(12,2) NOT NULL,
    is_recurring     BOOLEAN NOT NULL DEFAULT FALSE
);

-- ---------------------------------------------------------------
-- 10. ANNIVERSARY AND GIFTS BUDGET
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS occasions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  VARCHAR NOT NULL,
    name          VARCHAR NOT NULL,
    date          TIMESTAMPTZ NOT NULL,
    recurring     BOOLEAN NOT NULL DEFAULT TRUE,
    budget_amount NUMERIC(12,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS occasion_sinking_funds (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    occasion_id          UUID REFERENCES occasions(id) ON DELETE CASCADE,
    monthly_contribution NUMERIC(12,2) NOT NULL,
    current_balance      NUMERIC(12,2) NOT NULL DEFAULT 0.00
);
ALTER TABLE occasion_sinking_funds ADD COLUMN IF NOT EXISTS current_balance NUMERIC(12,2) NOT NULL DEFAULT 0.00;

-- ---------------------------------------------------------------
-- 11. RETIREMENT PROJECTOR
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS retirement_settings (
    household_id           VARCHAR PRIMARY KEY,
    target_retirement_age  INT NOT NULL DEFAULT 60,
    monthly_contribution   NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    expected_return_rate   NUMERIC(5,2) NOT NULL DEFAULT 7.00,
    current_age            INT NOT NULL DEFAULT 30,
    current_savings        NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE retirement_settings ADD COLUMN IF NOT EXISTS current_age     INT NOT NULL DEFAULT 30;
ALTER TABLE retirement_settings ADD COLUMN IF NOT EXISTS current_savings NUMERIC(12,2) NOT NULL DEFAULT 0.00;
ALTER TABLE retirement_settings ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ NOT NULL DEFAULT now();

-- ---------------------------------------------------------------
-- 12. EMERGENCY FUND TRACKER
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS emergency_funds (
    household_id   VARCHAR PRIMARY KEY,
    target_amount  NUMERIC(12,2) NOT NULL,
    current_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    months_target  INT NOT NULL DEFAULT 6,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE emergency_funds ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ---------------------------------------------------------------
-- 13. AI MONEY COACH INSIGHTS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_insights (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id VARCHAR NOT NULL,
    insight_text TEXT NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    type         VARCHAR NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_insights_household ON ai_insights(household_id, generated_at DESC);

-- ---------------------------------------------------------------
-- 14. MONEY PERSONALITY QUIZ RESULTS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS money_personalities (
    user_id          VARCHAR PRIMARY KEY,
    personality_type VARCHAR NOT NULL,
    quiz_answers     JSONB NOT NULL,
    taken_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- 15. SUBSCRIPTION MANAGER
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id      VARCHAR NOT NULL,
    owner_user_id     VARCHAR,
    name              VARCHAR NOT NULL,
    amount            NUMERIC(12,2) NOT NULL,
    billing_cycle     VARCHAR NOT NULL DEFAULT 'monthly',
    next_billing_date TIMESTAMPTZ NOT NULL,
    category          VARCHAR NOT NULL DEFAULT 'Entertainment',
    logo_url          VARCHAR,
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS owner_user_id     VARCHAR;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS billing_cycle     VARCHAR NOT NULL DEFAULT 'monthly';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS next_billing_date TIMESTAMPTZ;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS category          VARCHAR NOT NULL DEFAULT 'Entertainment';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS logo_url          VARCHAR;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS is_active         BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS created_at        TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_subs_household ON subscriptions(household_id, is_active);

-- ---------------------------------------------------------------
-- 16. BIG PURCHASE APPROVAL REQUESTS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS purchase_requests (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id VARCHAR NOT NULL,
    requester_id VARCHAR NOT NULL,
    item_name    VARCHAR NOT NULL,
    amount       NUMERIC(12,2) NOT NULL,
    reason       TEXT,
    status       VARCHAR NOT NULL DEFAULT 'pending',
    reviewed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE purchase_requests ADD COLUMN IF NOT EXISTS reason      TEXT;
ALTER TABLE purchase_requests ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_purchase_req_household ON purchase_requests(household_id, status);

-- ---------------------------------------------------------------
-- 17. TRANSACTION REACTIONS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_reactions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    user_id        VARCHAR NOT NULL,
    emoji          VARCHAR NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (transaction_id, user_id, emoji)
);

-- ---------------------------------------------------------------
-- 18. TRANSACTION COMMENTS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_comments (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    user_id        VARCHAR NOT NULL,
    comment_text   TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- 19. MONTHLY REPORT CARDS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS monthly_reports (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   VARCHAR NOT NULL,
    year           INT NOT NULL,
    month          INT NOT NULL CHECK (month >= 1 AND month <= 12),
    total_income   NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_expenses NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    savings_rate   NUMERIC(5,2),
    grade          VARCHAR(2),
    summary_json   JSONB,
    generated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (household_id, year, month)
);
ALTER TABLE monthly_reports ADD COLUMN IF NOT EXISTS savings_rate NUMERIC(5,2);
ALTER TABLE monthly_reports ADD COLUMN IF NOT EXISTS grade        VARCHAR(2);
ALTER TABLE monthly_reports ADD COLUMN IF NOT EXISTS summary_json JSONB;

-- ---------------------------------------------------------------
-- 20. CATEGORY BUDGETS
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS category_budgets (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id VARCHAR NOT NULL,
    category     VARCHAR NOT NULL,
    budget_limit NUMERIC(12,2) NOT NULL,
    period       VARCHAR NOT NULL DEFAULT 'monthly',
    UNIQUE (household_id, category, period)
);

-- =============================================================
-- ENABLE RLS
-- =============================================================
ALTER TABLE wallets                ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_splits     ENABLE ROW LEVEL SECURITY;
ALTER TABLE income_entries         ENABLE ROW LEVEL SECURITY;
ALTER TABLE net_worth_snapshots    ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets_liabilities     ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkins               ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE life_events            ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_cost_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE occasions              ENABLE ROW LEVEL SECURITY;
ALTER TABLE occasion_sinking_funds ENABLE ROW LEVEL SECURITY;
ALTER TABLE retirement_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_funds        ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_insights            ENABLE ROW LEVEL SECURITY;
ALTER TABLE money_personalities    ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_requests      ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_reactions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_comments   ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_reports        ENABLE ROW LEVEL SECURITY;
ALTER TABLE category_budgets       ENABLE ROW LEVEL SECURITY;

-- =============================================================
-- HELPER FUNCTION
-- Cast BOTH sides to TEXT — works for UUID and VARCHAR columns
-- =============================================================
CREATE OR REPLACE FUNCTION get_my_household_id()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER AS $$
    SELECT household_id::TEXT
    FROM household_members
    WHERE user_id::TEXT = auth.uid()::TEXT
    LIMIT 1;
$$;

-- =============================================================
-- RLS POLICIES
-- KEY PATTERN: always cast BOTH sides to TEXT
--   auth.uid()::TEXT = column::TEXT
-- This works whether the column is UUID, VARCHAR, or TEXT.
-- =============================================================
DROP POLICY IF EXISTS "wallet_owner_policy"       ON wallets;
DROP POLICY IF EXISTS "income_owner_policy"        ON income_entries;
DROP POLICY IF EXISTS "personality_owner_policy"   ON money_personalities;
DROP POLICY IF EXISTS "alerts_policy"              ON alerts;
DROP POLICY IF EXISTS "splits_policy"              ON transaction_splits;
DROP POLICY IF EXISTS "reactions_policy"           ON transaction_reactions;
DROP POLICY IF EXISTS "comments_policy"            ON transaction_comments;
DROP POLICY IF EXISTS "household_net_worth"        ON net_worth_snapshots;
DROP POLICY IF EXISTS "household_assets"           ON assets_liabilities;
DROP POLICY IF EXISTS "household_checkins"         ON checkins;
DROP POLICY IF EXISTS "household_life_events"      ON life_events;
DROP POLICY IF EXISTS "household_occasions"        ON occasions;
DROP POLICY IF EXISTS "household_retirement"       ON retirement_settings;
DROP POLICY IF EXISTS "household_emergency"        ON emergency_funds;
DROP POLICY IF EXISTS "household_ai_insights"      ON ai_insights;
DROP POLICY IF EXISTS "household_subscriptions"    ON subscriptions;
DROP POLICY IF EXISTS "household_purchases"        ON purchase_requests;
DROP POLICY IF EXISTS "household_monthly_reports"  ON monthly_reports;
DROP POLICY IF EXISTS "household_category_budgets" ON category_budgets;

-- wallets: owner_user_id NULL = shared (visible to all household members)
CREATE POLICY "wallet_owner_policy" ON wallets
    FOR ALL USING (
        owner_user_id IS NULL
        OR auth.uid()::TEXT = owner_user_id::TEXT
    );

CREATE POLICY "income_owner_policy" ON income_entries
    FOR ALL USING (auth.uid()::TEXT = user_id::TEXT);

CREATE POLICY "personality_owner_policy" ON money_personalities
    FOR ALL USING (auth.uid()::TEXT = user_id::TEXT);

CREATE POLICY "alerts_policy" ON alerts
    FOR ALL USING (user_id IS NULL OR auth.uid()::TEXT = user_id::TEXT);

CREATE POLICY "splits_policy" ON transaction_splits
    FOR ALL USING (auth.uid()::TEXT = user_id::TEXT);

CREATE POLICY "reactions_policy" ON transaction_reactions
    FOR ALL USING (auth.uid()::TEXT = user_id::TEXT);

CREATE POLICY "comments_policy" ON transaction_comments
    FOR ALL USING (auth.uid()::TEXT = user_id::TEXT);

CREATE POLICY "household_net_worth" ON net_worth_snapshots
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_assets" ON assets_liabilities
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_checkins" ON checkins
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_life_events" ON life_events
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_occasions" ON occasions
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_retirement" ON retirement_settings
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_emergency" ON emergency_funds
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_ai_insights" ON ai_insights
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_subscriptions" ON subscriptions
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_purchases" ON purchase_requests
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_monthly_reports" ON monthly_reports
    FOR ALL USING (household_id::TEXT = get_my_household_id());

CREATE POLICY "household_category_budgets" ON category_budgets
    FOR ALL USING (household_id::TEXT = get_my_household_id());

-- =============================================================
-- END OF MIGRATION
-- =============================================================
