-- معسكر نقلة — initial schema (Cloudflare D1 / SQLite)
-- Timestamps are UTC ISO strings; dates are Aden local 'YYYY-MM-DD'; money is whole rials.

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('manager','member')),
  specialty TEXT,
  phone TEXT,
  color TEXT,
  password_hash TEXT NOT NULL,
  session_version INTEGER NOT NULL DEFAULT 1,
  must_change_password INTEGER NOT NULL DEFAULT 0,
  settings TEXT NOT NULL DEFAULT '{}',
  distribution_balance REAL NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE member_slots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  dow INTEGER NOT NULL CHECK (dow BETWEEN 0 AND 6),
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'university' CHECK (kind IN ('university','work','other')),
  label TEXT
);
CREATE INDEX idx_member_slots_user ON member_slots(user_id);

CREATE TABLE absences (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  reason TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE INDEX idx_absences_user ON absences(user_id, start_date);

CREATE TABLE chores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  icon TEXT,
  frequency TEXT NOT NULL CHECK (frequency IN ('daily','days','weekly')),
  days TEXT NOT NULL DEFAULT '[]',
  weekly_day INTEGER,
  points INTEGER NOT NULL CHECK (points BETWEEN 1 AND 5),
  people_count INTEGER NOT NULL DEFAULT 1 CHECK (people_count BETWEEN 1 AND 8),
  slot TEXT NOT NULL DEFAULT 'any' CHECK (slot IN ('morning','afternoon','evening','any')),
  active INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE distributions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  week_start TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  generated_at TEXT NOT NULL,
  published_at TEXT,
  published_by INTEGER
);

CREATE TABLE distribution_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  distribution_id INTEGER NOT NULL REFERENCES distributions(id) ON DELETE CASCADE,
  chore_id INTEGER NOT NULL REFERENCES chores(id),
  date TEXT NOT NULL,
  slot TEXT NOT NULL,
  user_id INTEGER REFERENCES users(id),
  points INTEGER NOT NULL,
  task_id INTEGER
);
CREATE INDEX idx_dist_items ON distribution_items(distribution_id, date);

CREATE TABLE distribution_balances (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  distribution_id INTEGER NOT NULL REFERENCES distributions(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id),
  assigned REAL NOT NULL,
  expected REAL NOT NULL,
  balance_before REAL NOT NULL,
  balance_after REAL NOT NULL
);

CREATE TABLE projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  client TEXT,
  description TEXT,
  deadline TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','on_hold','closed')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('house','company','personal')),
  title TEXT NOT NULL,
  details TEXT,
  assignee_id INTEGER REFERENCES users(id),
  project_id INTEGER REFERENCES projects(id),
  chore_id INTEGER REFERENCES chores(id),
  distribution_item_id INTEGER,
  specialty TEXT,
  due_date TEXT,
  due_time TEXT,
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('normal','high','urgent')),
  size INTEGER NOT NULL DEFAULT 1,
  recurrence TEXT NOT NULL DEFAULT 'none' CHECK (recurrence IN ('none','daily','weekly')),
  needs_approval INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_progress','submitted','approved','returned')),
  checklist TEXT NOT NULL DEFAULT '[]',
  attachments TEXT NOT NULL DEFAULT '[]',
  completion_note TEXT,
  completion_url TEXT,
  return_note TEXT,
  group_id TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER,
  started_at TEXT,
  submitted_at TEXT,
  approved_at TEXT,
  approved_by INTEGER,
  reminded_at TEXT,
  overdue_notified_at TEXT,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_tasks_assignee ON tasks(assignee_id, due_date);
CREATE INDEX idx_tasks_kind_due ON tasks(kind, due_date);
CREATE INDEX idx_tasks_project ON tasks(project_id);

CREATE TABLE swap_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL REFERENCES tasks(id),
  counter_task_id INTEGER REFERENCES tasks(id),
  from_user_id INTEGER NOT NULL REFERENCES users(id),
  to_user_id INTEGER NOT NULL REFERENCES users(id),
  note TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','cancelled')),
  created_at TEXT NOT NULL,
  responded_at TEXT,
  deleted_at TEXT
);
CREATE INDEX idx_swaps_users ON swap_requests(to_user_id, status);

CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'meeting' CHECK (kind IN ('meeting','deadline','other')),
  date TEXT NOT NULL,
  start_time TEXT,
  end_time TEXT,
  everyone INTEGER NOT NULL DEFAULT 1,
  member_ids TEXT NOT NULL DEFAULT '[]',
  notes TEXT,
  created_by INTEGER,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_events_date ON events(date);

-- Shared money
CREATE TABLE contribution_periods (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  amount_per_member INTEGER NOT NULL CHECK (amount_per_member >= 0),
  due_date TEXT,
  created_by INTEGER,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE contributions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  period_id INTEGER NOT NULL REFERENCES contribution_periods(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount_due INTEGER NOT NULL CHECK (amount_due >= 0),
  UNIQUE (period_id, user_id)
);

CREATE TABLE contribution_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contribution_id INTEGER NOT NULL REFERENCES contributions(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  date TEXT NOT NULL,
  note TEXT,
  created_by INTEGER,
  deleted_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE shared_expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'other',
  amount INTEGER NOT NULL CHECK (amount > 0),
  date TEXT NOT NULL,
  paid_from_fund INTEGER NOT NULL DEFAULT 0,
  payer_id INTEGER REFERENCES users(id),
  split_member_ids TEXT NOT NULL DEFAULT '[]',
  note TEXT,
  attachment_url TEXT,
  created_by INTEGER,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_shared_expenses_date ON shared_expenses(date);

CREATE TABLE settlements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_user_id INTEGER NOT NULL REFERENCES users(id),
  to_user_id INTEGER NOT NULL REFERENCES users(id),
  amount INTEGER NOT NULL CHECK (amount > 0),
  date TEXT NOT NULL,
  note TEXT,
  created_by INTEGER,
  deleted_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE debts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  creditor_id INTEGER NOT NULL REFERENCES users(id),
  debtor_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT,
  amount INTEGER NOT NULL CHECK (amount > 0),
  due_date TEXT,
  note TEXT,
  settled_at TEXT,
  created_by INTEGER,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE debt_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  debt_id INTEGER NOT NULL REFERENCES debts(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  date TEXT NOT NULL,
  note TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL
);

-- Personal (visible to the owner only)
CREATE TABLE prayer_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  date TEXT NOT NULL,
  prayer TEXT NOT NULL CHECK (prayer IN ('fajr','dhuhr','asr','maghrib','isha')),
  UNIQUE (user_id, date, prayer)
);

CREATE TABLE sleep_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  date TEXT NOT NULL,
  slept_at TEXT NOT NULL,
  woke_at TEXT NOT NULL,
  UNIQUE (user_id, date)
);

CREATE TABLE workouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  date TEXT NOT NULL,
  type TEXT NOT NULL,
  duration_min INTEGER,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_workouts_user ON workouts(user_id, date);

CREATE TABLE goals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'personal',
  target_date TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE goal_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  goal_id INTEGER NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  done_at TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE habits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  days TEXT NOT NULL DEFAULT '"daily"',
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE habit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  UNIQUE (habit_id, date)
);

CREATE TABLE budget_weeks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  carried_in INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  saved_amount INTEGER,
  summary TEXT,
  created_at TEXT NOT NULL,
  closed_at TEXT
);
CREATE UNIQUE INDEX idx_budget_one_open ON budget_weeks(user_id) WHERE status = 'open';

CREATE TABLE budget_incomes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  week_id INTEGER NOT NULL REFERENCES budget_weeks(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0),
  source TEXT NOT NULL DEFAULT 'other',
  note TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE budget_essentials (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  week_id INTEGER NOT NULL REFERENCES budget_weeks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount >= 0)
);

CREATE TABLE budget_expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  week_id INTEGER NOT NULL REFERENCES budget_weeks(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0),
  category TEXT NOT NULL DEFAULT 'other',
  note TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_budget_expenses_week ON budget_expenses(week_id, date);

-- Notifications
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  link TEXT,
  urgent INTEGER NOT NULL DEFAULT 0,
  read_at TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_notifications_user ON notifications(user_id, created_at);

CREATE TABLE device_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  token TEXT NOT NULL UNIQUE,
  platform TEXT,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

-- Change history for shared items
CREATE TABLE activity_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  actor_id INTEGER,
  action TEXT NOT NULL,
  details TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_activity_entity ON activity_log(entity, entity_id);

CREATE TABLE login_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_login_attempts ON login_attempts(key, created_at);
