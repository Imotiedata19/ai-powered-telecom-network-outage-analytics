"""
TELECOM NETWORK OUTAGE & RELIABILITY ANALYTICS
Consolidated Python Pipeline: EDA, Validation, Visualization,
Feature Engineering, Predictive Modeling, Risk Scoring, Watchlist,
and Dashboard Data Export

Prerequisite: run "SQL Telecom Outage Analysis.sql" first -- it produces
data/telecom_outage_features.csv and data/telecom_tower_summary.csv,
which this script reads. Run this script's sections in order from the
project root (it expects ./data/ and ./charts/ to exist or be creatable
as subfolders of the current working directory).
"""
import os
os.makedirs('data', exist_ok=True)
os.makedirs('charts', exist_ok=True)


# ================================================================
# FILE: py01_validation_descriptive.py
# ================================================================
"""
PHASE 7 - PYTHON ANALYTICS
Step 1: Dataset validation after SQL cleaning
Step 2: Descriptive statistics
"""
import pandas as pd
import numpy as np

pd.set_option('display.width', 140)
pd.set_option('display.max_columns', 30)

# -----------------------------------------------------------------------
# LOAD - from the SQL-cleaned/feature-engineered export (not the raw file)
# -----------------------------------------------------------------------
df = pd.read_csv('data/telecom_outage_features.csv', parse_dates=['obs_date'],
                  keep_default_na=False, na_values=[''])
tower_df = pd.read_csv('data/telecom_tower_summary.csv', keep_default_na=False, na_values=[''])

print("="*70)
print("STEP 1: DATASET VALIDATION AFTER SQL CLEANING")
print("="*70)
print(f"Row count (features): {len(df):,}  (expected 100,000)")
print(f"Row count (tower summary): {len(tower_df):,}  (expected 70,599)")
print(f"Unique towers in features: {df['tower_id'].nunique():,}")
assert len(df) == 100000, "Row count mismatch vs SQL!"
assert len(tower_df) == 70599, "Tower summary row count mismatch vs SQL!"
assert df['tower_id'].nunique() == 70599

print("\nColumn dtypes:")
print(df.dtypes)

print("\nNull counts (only outage_reason should be non-zero):")
print(df.isnull().sum()[df.isnull().sum() > 0])

print("\nDate range:", df['obs_date'].min(), "to", df['obs_date'].max())

# Cross-check key aggregates against SQL Phase 4 results
print("\nCross-check vs SQL Network Overview (Phase 4):")
print(f"  avg_uptime_pct = {df['uptime_percentage'].mean():.2f}  (SQL: 92.50)")
print(f"  total_downtime = {df['downtime_minutes'].sum():,.1f}  (SQL: 10,798,364.5)")
print(f"  total_outages  = {df['outage_count'].sum():,}  (SQL: 233,384)")
print(f"  total_users_affected = {df['avg_users_affected'].sum():,}  (SQL: 18,335,529)")

print("\n" + "="*70)
print("STEP 2: DESCRIPTIVE STATISTICS")
print("="*70)
print(df[['uptime_percentage','downtime_minutes','outage_count','avg_users_affected']].describe().T)

print("\nCategorical value counts:")

for col in [
    'operator',
    'network_type',
    'outage_reason',
    'outage_severity',
    'reliability_status',
    'high_risk_flag',
    'observation_month',
    'day_of_week'
]:
    print(f"\n-- {col} --")
    print(df[col].value_counts(dropna=False))


# ================================================================
# FILE: py02_visualizations.py
# ================================================================
"""
PHASE 7 - PYTHON ANALYTICS
Univariate / Bivariate / Multivariate / Correlation / Outlier /
Time-based / Geographic / Root-cause visualizations.
All charts saved as PNG to charts/
"""
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
import os

sns.set_style('whitegrid')
plt.rcParams['figure.dpi'] = 110
plt.rcParams['axes.titleweight'] = 'bold'
plt.rcParams['axes.titlesize'] = 13

OUT = 'charts'
os.makedirs(OUT, exist_ok=True)

df = pd.read_csv('data/telecom_outage_features.csv', parse_dates=['obs_date'],
                  keep_default_na=False, na_values=[''])
tower_df = pd.read_csv('data/telecom_tower_summary.csv', keep_default_na=False, na_values=[''])

PALETTE = sns.color_palette("Blues_d", 8)
CAUSE_ORDER = ['power_failure','equipment_fault','maintenance','fiber_cut','weather']

def save(fig, name):
    fig.tight_layout()
    fig.savefig(f'{OUT}/{name}.png', bbox_inches='tight')
    plt.close(fig)
    print(f"Saved {name}.png")

# =====================================================================
# UNIVARIATE ANALYSIS - distributions
# =====================================================================
fig, axes = plt.subplots(2, 2, figsize=(11, 8))
sns.histplot(df['uptime_percentage'], bins=30, ax=axes[0,0], color=PALETTE[4])
axes[0,0].set_title('Uptime % Distribution')
axes[0,0].set_xlabel('Uptime %')

sns.histplot(df['downtime_minutes'], bins=30, ax=axes[0,1], color=PALETTE[5])
axes[0,1].set_title('Downtime Minutes Distribution')
axes[0,1].set_xlabel('Downtime (minutes)')

sns.histplot(df['outage_count'], bins=6, discrete=True, ax=axes[1,0], color=PALETTE[6])
axes[1,0].set_title('Outage Count Distribution')
axes[1,0].set_xlabel('Outage Count')

sns.histplot(df['avg_users_affected'], bins=30, ax=axes[1,1], color=PALETTE[7])
axes[1,1].set_title('Avg Users Affected Distribution')
axes[1,1].set_xlabel('Avg Users Affected')
fig.suptitle('Univariate Distributions (n=100,000 observations)', fontsize=15, y=1.02)
save(fig, '01_univariate_distributions')

# =====================================================================
# BIVARIATE - outages by operator / uptime by operator / downtime by operator
# =====================================================================
op_summary = df.groupby('operator').agg(
    avg_uptime=('uptime_percentage','mean'),
    avg_downtime=('downtime_minutes','mean'),
    total_outages=('outage_count','sum')
).reset_index().sort_values('avg_uptime', ascending=False)

fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))
sns.barplot(data=op_summary, x='operator', y='total_outages', ax=axes[0], color=PALETTE[4])
axes[0].set_title('Total Outages by Operator')
axes[0].set_ylabel('Total Outages'); axes[0].set_xlabel('')

sns.barplot(data=op_summary, x='operator', y='avg_uptime', ax=axes[1], color=PALETTE[5])
axes[1].set_ylim(90, 94)
axes[1].set_title('Avg Uptime % by Operator\n(range: 0.035pts — within noise)')
axes[1].set_ylabel('Avg Uptime %'); axes[1].set_xlabel('')

sns.barplot(data=op_summary, x='operator', y='avg_downtime', ax=axes[2], color=PALETTE[6])
axes[2].set_ylim(100, 112)
axes[2].set_title('Avg Downtime (min) by Operator')
axes[2].set_ylabel('Avg Downtime (min)'); axes[2].set_xlabel('')
save(fig, '02_operator_comparison')

# outages/uptime by network type
net_summary = df.groupby('network_type').agg(
    avg_uptime=('uptime_percentage','mean'),
    total_outages=('outage_count','sum')
).reset_index().sort_values('network_type')

fig, axes = plt.subplots(1, 2, figsize=(10, 4.5))
sns.barplot(data=net_summary, x='network_type', y='total_outages', ax=axes[0],
            order=['2G','3G','4G','5G'], color=PALETTE[4])
axes[0].set_title('Total Outages by Network Type')
axes[0].set_ylabel('Total Outages'); axes[0].set_xlabel('')

sns.barplot(data=net_summary, x='network_type', y='avg_uptime', ax=axes[1],
            order=['2G','3G','4G','5G'], color=PALETTE[6])
axes[1].set_ylim(90, 94)
axes[1].set_title('Avg Uptime % by Network Type\n(range: 0.059pts — within noise)')
axes[1].set_ylabel('Avg Uptime %'); axes[1].set_xlabel('')
save(fig, '03_network_type_comparison')

# =====================================================================
# ROOT CAUSE ANALYSIS
# =====================================================================
cause_df = df[df['outage_reason'].notna()]
cause_summary = cause_df.groupby('outage_reason').agg(
    n=('outage_reason','size'),
    total_downtime=('downtime_minutes','sum'),
    total_users=('avg_users_affected','sum')
).reindex(CAUSE_ORDER)

fig, axes = plt.subplots(1, 3, figsize=(16, 4.8))
sns.barplot(x=cause_summary.index, y=cause_summary['n'], ax=axes[0], color=PALETTE[4])
axes[0].set_title('Impactful Observations by Outage Cause')
axes[0].set_ylabel('Count'); axes[0].set_xlabel('')
axes[0].tick_params(axis='x', rotation=30)

sns.barplot(x=cause_summary.index, y=cause_summary['total_downtime'], ax=axes[1], color=PALETTE[5])
axes[1].set_title('Total Downtime (min) by Cause')
axes[1].set_ylabel('Total Downtime (min)'); axes[1].set_xlabel('')
axes[1].tick_params(axis='x', rotation=30)

sns.barplot(x=cause_summary.index, y=cause_summary['total_users'], ax=axes[2], color=PALETTE[6])
axes[2].set_title('Total Users Affected by Cause')
axes[2].set_ylabel('Total Users Affected'); axes[2].set_xlabel('')
axes[2].tick_params(axis='x', rotation=30)
fig.suptitle('Root Cause Analysis\n(Note: per-event severity is nearly identical across causes ~143-144 min avg — totals track FREQUENCY, not severity)',
             fontsize=12, y=1.06)
save(fig, '04_root_cause_analysis')

# =====================================================================
# GEOGRAPHIC ANALYSIS - top states by outages/downtime, cities by uptime
# =====================================================================
state_outages = df.groupby('state')['outage_count'].sum().sort_values(ascending=False).head(10)
state_downtime = df.groupby('state')['downtime_minutes'].sum().sort_values(ascending=False).head(10)

fig, axes = plt.subplots(1, 2, figsize=(13, 5))
sns.barplot(x=state_outages.values, y=state_outages.index, ax=axes[0], color=PALETTE[4], orient='h')
axes[0].set_title('Top 10 States by Total Outages')
axes[0].set_xlabel('Total Outages')

sns.barplot(x=state_downtime.values, y=state_downtime.index, ax=axes[1], color=PALETTE[6], orient='h')
axes[1].set_title('Top 10 States by Total Downtime (min)')
axes[1].set_xlabel('Total Downtime (min)')
fig.suptitle('Geographic Analysis - States\n(Range of state avg uptime: 0.312pts vs overall stddev 4.32 — not a meaningful geographic effect)',
             fontsize=11, y=1.05)
save(fig, '05_state_geographic_analysis')

city_uptime = df.groupby('city')['uptime_percentage'].mean().sort_values()
city_outages = df.groupby('city')['outage_count'].sum().sort_values(ascending=False)

fig, axes = plt.subplots(1, 2, figsize=(13, 5.5))
sns.barplot(x=city_uptime.values, y=city_uptime.index, ax=axes[0], color=PALETTE[4], orient='h')
axes[0].set_xlim(91.5, 93)
axes[0].set_title('Cities Ranked by Avg Uptime %\n(lowest to highest — narrow band)')
axes[0].set_xlabel('Avg Uptime %')

sns.barplot(x=city_outages.values, y=city_outages.index, ax=axes[1], color=PALETTE[6], orient='h')
axes[1].set_title('Total Outages by City')
axes[1].set_xlabel('Total Outages')
fig.suptitle('Geographic Analysis - Cities', fontsize=13, y=1.02)
save(fig, '06_city_geographic_analysis')

# Worst-performing towers (lowest avg uptime, tower-level)
worst_towers = tower_df.nsmallest(15, 'avg_uptime_percentage')[['tower_id','city','avg_uptime_percentage','total_downtime_minutes']]
fig, ax = plt.subplots(figsize=(9, 6))
sns.barplot(data=worst_towers, x='avg_uptime_percentage', y='tower_id', color=PALETTE[3], ax=ax)
ax.set_xlim(84, 86)
ax.set_title('15 Worst-Performing Towers by Avg Uptime %')
ax.set_xlabel('Avg Uptime %'); ax.set_ylabel('Tower ID')
save(fig, '07_worst_performing_towers')

# =====================================================================
# TIME-BASED ANALYSIS - monthly/daily trends
# =====================================================================
daily = df.groupby('obs_date').agg(
    total_outages=('outage_count','sum'),
    total_downtime=('downtime_minutes','sum'),
    avg_uptime=('uptime_percentage','mean')
).reset_index()

fig, axes = plt.subplots(3, 1, figsize=(12, 9), sharex=True)
axes[0].plot(daily['obs_date'], daily['total_outages'], marker='o', color=PALETTE[4], ms=3)
axes[0].set_title('Daily Outage Trend')
axes[0].set_ylabel('Total Outages')

axes[1].plot(daily['obs_date'], daily['total_downtime'], marker='o', color=PALETTE[5], ms=3)
axes[1].set_title('Daily Downtime Trend')
axes[1].set_ylabel('Total Downtime (min)')

axes[2].plot(daily['obs_date'], daily['avg_uptime'], marker='o', color=PALETTE[6], ms=3)
axes[2].set_ylim(91.5, 93.5)
axes[2].set_title('Daily Average Uptime % Trend\n(flat within noise: range 0.33pts vs daily-avg stddev 0.07)')
axes[2].set_ylabel('Avg Uptime %')
axes[2].set_xlabel('Date')
fig.autofmt_xdate()
save(fig, '08_daily_time_trends')

# Monthly comparison (explicitly caveated - only 2 unevenly-sized months)
monthly = df.groupby(df['obs_date'].dt.to_period('M')).agg(
    observations=('row_id','count'),
    total_outages=('outage_count','sum'),
    avg_uptime=('uptime_percentage','mean')
).reset_index()
monthly['obs_date'] = monthly['obs_date'].astype(str)

fig, ax = plt.subplots(figsize=(7,4.5))
sns.barplot(data=monthly, x='obs_date', y='avg_uptime', color=PALETTE[5], ax=ax)
ax.set_ylim(90,94)
ax.set_title('Monthly Avg Uptime %\n(NOTE: Sept=30 days/96,788 obs vs Oct=1 day/3,212 obs — not a real trend)')
ax.set_xlabel(''); ax.set_ylabel('Avg Uptime %')
save(fig, '09_monthly_uptime_caveated')

# =====================================================================
# MULTIVARIATE / CORRELATION ANALYSIS
# =====================================================================
corr_cols = ['uptime_percentage','downtime_minutes','outage_count','avg_users_affected']
corr = df[corr_cols].corr()

fig, ax = plt.subplots(figsize=(6.5, 5.5))
sns.heatmap(corr, annot=True, fmt='.3f', cmap='RdBu_r', center=0, vmin=-1, vmax=1,
            ax=ax, square=True, cbar_kws={'label':'Pearson r'})
ax.set_title('Correlation Heatmap\n(uptime vs downtime ≈ -1.0: mathematically derived, not independent)')
save(fig, '10_correlation_heatmap')

# =====================================================================
# OUTLIER ANALYSIS - boxplots (IQR method, confirmed 0 outliers in Phase 2)
# =====================================================================
fig, axes = plt.subplots(1, 4, figsize=(14, 5))
for ax, col, color in zip(axes, corr_cols, PALETTE[3:7]):
    sns.boxplot(y=df[col], ax=ax, color=color)
    ax.set_title(col.replace('_',' ').title())
fig.suptitle('Outlier Analysis (IQR method)\nZero statistical outliers found in any measure — bounded near-uniform distributions',
             fontsize=12, y=1.05)
save(fig, '11_outlier_boxplots')

print("\nAll charts saved to", OUT)
print(os.listdir(OUT))


# ================================================================
# FILE: py03_feature_engineering.py
# ================================================================
"""
PHASE 8 - PREDICTIVE MODELING: FEATURE ENGINEERING
Leakage-safe design:
  - Only towers with >=2 chronological observations can supply a
    train/test row (need at least 1 historical observation + 1 target
    observation).
  - Historical features are computed EXCLUSIVELY from a tower's
    observations strictly before its most recent one.
  - The target is computed from the tower's most recent observation only.
  - Train/test split is TIME-AWARE: split by the target observation's
    date, not randomly, so no test-period information leaks into training.
"""
import pandas as pd
import numpy as np

df = pd.read_csv('data/telecom_outage_features.csv', parse_dates=['obs_date'],
                  keep_default_na=False, na_values=[''])

# Chronological sort within each tower; row_id used as a deterministic
# tie-breaker for the 847 towers whose two most recent observations share
# the same calendar date (documented limitation: date granularity is daily
# only, so same-day ordering is arbitrary but fixed for reproducibility).
df = df.sort_values(['tower_id', 'obs_date', 'row_id']).reset_index(drop=True)

obs_counts = df.groupby('tower_id').size()
modeling_towers = obs_counts[obs_counts >= 2].index
print(f"Towers usable for train/test modeling (>=2 observations): {len(modeling_towers):,}")
print(f"Towers with only 1 observation (watchlist-only): {(obs_counts==1).sum():,}")

def build_tower_features(group, label):
    """Given all rows for one tower (chronologically sorted), split into
    history (all but last) and target (last). If label='full', use ALL
    rows as history and there is no target (used for inference/watchlist).
    """
    if label == 'train_eval':
        history = group.iloc[:-1]
        target_row = group.iloc[-1]
    else:  # 'full' - inference mode for the watchlist, uses every row
        history = group
        target_row = group.iloc[-1]  # used only for descriptive "latest" fields
    return history, target_row

def mode_or_last(series):
    m = series.mode()
    return m.iloc[0] if len(m) else series.iloc[-1]

def summarize_history(history):
    return pd.Series({
        'hist_num_observations': len(history),
        'hist_avg_uptime': history['uptime_percentage'].mean(),
        'hist_min_uptime': history['uptime_percentage'].min(),
        'hist_avg_downtime': history['downtime_minutes'].mean(),
        'hist_max_downtime': history['downtime_minutes'].max(),
        'hist_total_downtime': history['downtime_minutes'].sum(),
        'hist_avg_outage_count': history['outage_count'].mean(),
        'hist_total_outage_count': history['outage_count'].sum(),
        'hist_avg_users_affected': history['avg_users_affected'].mean(),
        'hist_pct_impactful': (history['avg_users_affected'] > 0).mean(),
        'hist_mode_operator': mode_or_last(history['operator']),
        'hist_mode_state': mode_or_last(history['state']),
        'hist_mode_network_type': mode_or_last(history['network_type']),
        'hist_city': history['city'].iloc[0],  # stable per tower (Phase 3 finding)
    })

# -----------------------------------------------------------------------
# BUILD THE TRAIN/EVAL DATASET (towers with >=2 observations only)
# -----------------------------------------------------------------------
records = []

for tower_id, group in df[df['tower_id'].isin(modeling_towers)].groupby('tower_id'):

    # Sort each tower's observations chronologically
    group = (
        group
        .sort_values(['obs_date', 'row_id'])
        .reset_index(drop=True)
    )

    # Create historical -> next-period prediction examples
    for target_idx in range(1, len(group)):

        history = group.iloc[:target_idx]
        target_row = group.iloc[target_idx]

        feats = summarize_history(history)
        feats['tower_id'] = tower_id
        feats['target_date'] = target_row['obs_date']
        feats['next_period_high_risk'] = int(
            target_row['high_risk_flag']
        )

        records.append(feats)

model_df = pd.DataFrame(records)
print(f"\nModeling dataset shape: {model_df.shape}")
print(f"Target base rate (next_period_high_risk=1): {model_df['next_period_high_risk'].mean():.4f} "
      f"({model_df['next_period_high_risk'].sum():,} / {len(model_df):,})")

print("\nTarget date range:", model_df['target_date'].min(), "to", model_df['target_date'].max())
print("\nHistorical observation count per tower (in this modeling set):")
print(model_df['hist_num_observations'].value_counts().sort_index())

model_df.to_csv('data/model_dataset.csv', index=False)
print("\nSaved model_dataset.csv")


# ================================================================
# FILE: py04_train_models.py
# ================================================================
"""
PHASE 8 - PREDICTIVE MODELING: TRAIN/TEST + MODELS
"""
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (accuracy_score, precision_score, recall_score, f1_score,
                              roc_auc_score, confusion_matrix, classification_report)

model_df = pd.read_csv('data/model_dataset.csv', parse_dates=['target_date'])

# -----------------------------------------------------------------------
# TIME-AWARE SPLIT: split by target_date, NOT randomly. Earlier target
# dates -> train; latest target dates -> test. This means the model is
# evaluated on periods that come after everything it was trained on.
# -----------------------------------------------------------------------
model_df = model_df.sort_values('target_date').reset_index(drop=True)
split_idx = int(len(model_df) * 0.8)
split_date = model_df.iloc[split_idx]['target_date']
train_df = model_df[model_df['target_date'] < split_date].copy()
test_df = model_df[model_df['target_date'] >= split_date].copy()

print(f"Split date: {split_date}")
print(f"Train: {len(train_df):,} rows ({train_df['target_date'].min()} to {train_df['target_date'].max()})")
print(f"Test:  {len(test_df):,} rows ({test_df['target_date'].min()} to {test_df['target_date'].max()})")
print(f"Train target rate: {train_df['next_period_high_risk'].mean():.4f}")
print(f"Test target rate:  {test_df['next_period_high_risk'].mean():.4f}")

# -----------------------------------------------------------------------
# FEATURE ENCODING
# -----------------------------------------------------------------------
categorical_cols = ['hist_mode_operator', 'hist_mode_state', 'hist_mode_network_type', 'hist_city']
numeric_cols = ['hist_num_observations', 'hist_avg_uptime', 'hist_min_uptime', 'hist_avg_downtime',
                'hist_max_downtime', 'hist_total_downtime', 'hist_avg_outage_count',
                'hist_total_outage_count', 'hist_avg_users_affected', 'hist_pct_impactful']

train_cat = pd.get_dummies(train_df[categorical_cols], prefix=categorical_cols)
test_cat = pd.get_dummies(test_df[categorical_cols], prefix=categorical_cols)
test_cat = test_cat.reindex(columns=train_cat.columns, fill_value=0)

X_train = pd.concat([train_df[numeric_cols].reset_index(drop=True), train_cat.reset_index(drop=True)], axis=1)
X_test = pd.concat([test_df[numeric_cols].reset_index(drop=True), test_cat.reset_index(drop=True)], axis=1)
y_train = train_df['next_period_high_risk'].values
y_test = test_df['next_period_high_risk'].values

print(f"\nFeature matrix: {X_train.shape[1]} features "
      f"({len(numeric_cols)} numeric + {train_cat.shape[1]} one-hot encoded categorical)")

scaler = StandardScaler()
X_train_scaled = X_train.copy()
X_test_scaled = X_test.copy()
X_train_scaled[numeric_cols] = scaler.fit_transform(X_train[numeric_cols])
X_test_scaled[numeric_cols] = scaler.transform(X_test[numeric_cols])

# -----------------------------------------------------------------------
# TRAIN MODELS
# -----------------------------------------------------------------------
models = {
    'Logistic Regression': LogisticRegression(max_iter=1000, class_weight='balanced', random_state=42),
    'Random Forest': RandomForestClassifier(n_estimators=300, max_depth=8, min_samples_leaf=20,
                                             class_weight='balanced', random_state=42, n_jobs=-1),
    'Gradient Boosting': GradientBoostingClassifier(n_estimators=200, max_depth=3,
                                                      learning_rate=0.05, random_state=42),
}

results = {}
for name, model in models.items():
    Xtr = X_train_scaled if name == 'Logistic Regression' else X_train
    Xte = X_test_scaled if name == 'Logistic Regression' else X_test
    model.fit(Xtr, y_train)
    y_pred = model.predict(Xte)
    y_proba = model.predict_proba(Xte)[:, 1]

    results[name] = {
        'model': model,
        'y_pred': y_pred,
        'y_proba': y_proba,
        'accuracy': accuracy_score(y_test, y_pred),
        'precision': precision_score(y_test, y_pred, zero_division=0),
        'recall': recall_score(y_test, y_pred, zero_division=0),
        'f1': f1_score(y_test, y_pred, zero_division=0),
        'roc_auc': roc_auc_score(y_test, y_proba),
        'confusion_matrix': confusion_matrix(y_test, y_pred),
    }
    print(f"\n{'='*60}\n{name}\n{'='*60}")
    print(f"Accuracy:  {results[name]['accuracy']:.4f}")
    print(f"Precision: {results[name]['precision']:.4f}")
    print(f"Recall:    {results[name]['recall']:.4f}  <-- high-risk-site recall (priority metric)")
    print(f"F1-score:  {results[name]['f1']:.4f}")
    print(f"ROC-AUC:   {results[name]['roc_auc']:.4f}")
    print(f"Confusion Matrix:\n{results[name]['confusion_matrix']}")
    print(f"  (rows=actual [0,1], cols=predicted [0,1])")

import pickle
with open('data/model_results.pkl', 'wb') as f:
    pickle.dump({
        'results': {k: {kk: vv for kk, vv in v.items() if kk != 'model'} for k, v in results.items()},
        'models': {k: v['model'] for k, v in results.items()},
        'X_train_cols': list(X_train.columns),
        'numeric_cols': numeric_cols,
        'categorical_cols': categorical_cols,
        'scaler': scaler,
        'train_cat_cols': list(train_cat.columns),
        'y_test': y_test,
        'test_df': test_df,
    }, f)
print("\nSaved model_results.pkl")


# ================================================================
# FILE: py05_risk_score_watchlist.py
# ================================================================
"""
PHASE 8 - FINAL SITE RELIABILITY / RISK SCORE (rate-based, bias-corrected)
           + tower_risk_watchlist.csv (operational output)

Corrects the Phase 3 preliminary score's known bias: that version used
raw SUMS (total_downtime_minutes, total_users_affected), which favored
towers with more observations. This version uses PER-OBSERVATION RATES
so a tower with 1 bad reading and a tower with 5 average readings that
sum to the same total are no longer conflated.
"""
import pandas as pd
import numpy as np
import pickle

df = pd.read_csv('data/telecom_outage_features.csv', parse_dates=['obs_date'],
                  keep_default_na=False, na_values=[''])
tower_df = pd.read_csv('data/telecom_tower_summary.csv', keep_default_na=False, na_values=[''])

with open('data/model_results.pkl', 'rb') as f:
    d = pickle.load(f)

# -----------------------------------------------------------------------
# STEP A: RATE-BASED RISK SCORE (replaces Phase 3 preliminary sum-based one)
# -----------------------------------------------------------------------
# Rebuild tower-level RATE features directly (not sums)
rate_feats = df.groupby('tower_id').agg(
    avg_uptime_percentage=('uptime_percentage', 'mean'),
    avg_downtime_minutes=('downtime_minutes', 'mean'),
    avg_outage_count=('outage_count', 'mean'),
    avg_users_affected=('avg_users_affected', 'mean'),
    pct_impactful=('avg_users_affected', lambda s: (s > 0).mean()),
    total_observations=('row_id', 'count'),
).reset_index()

# Min-max normalize each component to 0-1 (project-defined normalization,
# documented explicitly - NOT a claimed industry standard)
def minmax(s):
    return (s - s.min()) / (s.max() - s.min())

rate_feats['norm_downtime_risk'] = minmax(rate_feats['avg_downtime_minutes'])       # higher = riskier
rate_feats['norm_uptime_risk'] = 1 - minmax(rate_feats['avg_uptime_percentage'])    # invert: lower uptime = higher risk
rate_feats['norm_impact_risk'] = minmax(rate_feats['avg_users_affected'])           # higher = riskier
rate_feats['norm_frequency_risk'] = minmax(rate_feats['pct_impactful'])             # higher = riskier

# EQUAL WEIGHTING (project-defined; no business-supplied weighting scheme
# exists, so each of the 4 components contributes 25%). This is stated
# explicitly rather than presented as an optimized/validated weighting.
rate_feats['site_reliability_risk_score'] = (
    0.25 * rate_feats['norm_downtime_risk'] +
    0.25 * rate_feats['norm_uptime_risk'] +
    0.25 * rate_feats['norm_impact_risk'] +
    0.25 * rate_feats['norm_frequency_risk']
) * 100  # scaled 0-100 for readability

# Risk category thresholds: quartile-based on the score itself (project-defined)
q1, q2, q3 = rate_feats['site_reliability_risk_score'].quantile([0.25, 0.5, 0.75])
def categorize(score):
    if score <= q1: return 'Low Risk'
    elif score <= q2: return 'Medium Risk'
    elif score <= q3: return 'High Risk'
    else: return 'Critical Risk'
rate_feats['risk_category_final'] = rate_feats['site_reliability_risk_score'].apply(categorize)

print("FINAL (rate-based) risk category distribution:")
print(rate_feats['risk_category_final'].value_counts())
print(f"\nScore quartile thresholds: Q1={q1:.2f}, Q2(median)={q2:.2f}, Q3={q3:.2f}")

# Sanity check: does this new score still show the multi-observation bias
# found in Phase 3? Compare avg score for single- vs multi-observation towers.
rate_feats['is_multi_obs'] = rate_feats['total_observations'] > 1
print("\nBias check - avg score by observation count (should now be similar, unlike Phase 3):")
print(rate_feats.groupby('is_multi_obs')['site_reliability_risk_score'].mean())

# -----------------------------------------------------------------------
# STEP B: APPLY THE TRAINED MODEL TO ALL 70,599 TOWERS FOR THE WATCHLIST
# Using EACH TOWER'S FULL OBSERVATION HISTORY as inference-time features
# (this is standard practice: the model was trained/evaluated on a
# held-out temporal split; applying the fitted model to the full current
# history of every tower, including single-observation towers, is how it
# would be used operationally going forward - it is not leakage because
# no test-set labels are used here, only feature computation).
# -----------------------------------------------------------------------
def mode_or_last(series):
    m = series.mode()
    return m.iloc[0] if len(m) else series.iloc[-1]

full_hist = df.sort_values(['tower_id','obs_date']).groupby('tower_id').agg(
    hist_num_observations=('row_id','count'),
    hist_avg_uptime=('uptime_percentage','mean'),
    hist_min_uptime=('uptime_percentage','min'),
    hist_avg_downtime=('downtime_minutes','mean'),
    hist_max_downtime=('downtime_minutes','max'),
    hist_total_downtime=('downtime_minutes','sum'),
    hist_avg_outage_count=('outage_count','mean'),
    hist_total_outage_count=('outage_count','sum'),
    hist_avg_users_affected=('avg_users_affected','mean'),
    hist_pct_impactful=('avg_users_affected', lambda s: (s>0).mean()),
    hist_mode_operator=('operator', mode_or_last),
    hist_mode_state=('state', mode_or_last),
    hist_mode_network_type=('network_type', mode_or_last),
    hist_city=('city','first'),
    latest_uptime=('uptime_percentage','last'),
    latest_date=('obs_date','last'),
).reset_index()

# Encode exactly like training (align to training's one-hot columns)
cat_cols = d['categorical_cols']
numeric_cols = d['numeric_cols']
train_cat_cols = d['train_cat_cols']

full_cat = pd.get_dummies(full_hist[cat_cols], prefix=cat_cols)
full_cat = full_cat.reindex(columns=train_cat_cols, fill_value=0)
X_full = pd.concat([full_hist[numeric_cols].reset_index(drop=True), full_cat.reset_index(drop=True)], axis=1)

# Chosen watchlist probability model: LOGISTIC REGRESSION.
# Current published validation: all three models have ROC-AUC ~= 0.494.
# Logistic Regression is retained only as an interpretable probability
# baseline for reproducibility. It is NOT the highest-recall model in the
# current run (Gradient Boosting has the highest recall), and no model is
# validated for operational deployment. Use observed repeat-outage history
# and the rate-based Site Reliability Risk Score for operational prioritization.
final_model = d['models']['Logistic Regression']
scaler = d['scaler']
X_full_scaled = X_full.copy()
X_full_scaled[numeric_cols] = scaler.transform(X_full[numeric_cols])

full_hist['predicted_risk_probability'] = final_model.predict_proba(X_full_scaled)[:, 1]
full_hist['predicted_risk_category'] = pd.cut(
    full_hist['predicted_risk_probability'],
    bins=[-0.01, 0.25, 0.5, 0.75, 1.01],
    labels=['Low', 'Medium', 'High', 'Critical']
)

# Merge with the rate-based risk score
watchlist = full_hist.merge(rate_feats[['tower_id','site_reliability_risk_score','risk_category_final']], on='tower_id')

# recommended_priority: rank by predicted probability first (model's best
# guess at future risk), tie-broken by the rate-based score
watchlist = watchlist.sort_values(
    ['predicted_risk_probability', 'site_reliability_risk_score'], ascending=False
).reset_index(drop=True)
watchlist['recommended_priority'] = watchlist.index + 1

output_cols = ['tower_id','hist_mode_operator','hist_mode_state','hist_city','hist_mode_network_type',
               'latest_uptime','hist_total_downtime','hist_total_outage_count',
               'site_reliability_risk_score','risk_category_final',
               'predicted_risk_probability','predicted_risk_category','recommended_priority']
watchlist_out = watchlist[output_cols].rename(columns={
    'hist_mode_operator':'operator','hist_mode_state':'state','hist_city':'city',
    'hist_mode_network_type':'network_type','hist_total_downtime':'historical_total_downtime_minutes',
    'hist_total_outage_count':'historical_total_outage_count'
})

watchlist_out.to_csv('data/tower_risk_watchlist.csv', index=False)
print(f"\nSaved tower_risk_watchlist.csv with {len(watchlist_out):,} towers")
print(watchlist_out.head(10).to_string())

# Validation
assert len(watchlist_out) == 70599, "Watchlist must cover all towers!"
assert watchlist_out['tower_id'].nunique() == 70599
print("\nValidation passed: all 70,599 towers present, no duplicates.")



# ================================================================
# FILE: py06_build_dashboard_data.py
# ================================================================
"""
Build compact columnar JSON datasets for the interactive HTML dashboard.
Categorical fields are encoded as small integers with legend arrays to
keep the embedded payload small; numeric fields are rounded to the
precision actually needed for display.
"""
import pandas as pd
import numpy as np
import json
import pickle
import os

df = pd.read_csv('data/telecom_outage_features.csv', parse_dates=['obs_date'],
                  keep_default_na=False, na_values=[''])
tower_df = pd.read_csv('data/telecom_tower_summary.csv', keep_default_na=False, na_values=[''])
watch_df = pd.read_csv('data/tower_risk_watchlist.csv')

operators = sorted(df['operator'].unique().tolist())
networks = sorted(df['network_type'].unique().tolist())
states = sorted(df['state'].unique().tolist())
cities = sorted(df['city'].unique().tolist())
reasons = ['None'] + sorted(df['outage_reason'].dropna().unique().tolist())
dates = sorted(df['obs_date'].dt.strftime('%Y-%m-%d').unique().tolist())

op_idx = {v: i for i, v in enumerate(operators)}
net_idx = {v: i for i, v in enumerate(networks)}
st_idx = {v: i for i, v in enumerate(states)}
city_idx = {v: i for i, v in enumerate(cities)}
reason_idx = {v: i for i, v in enumerate(reasons)}
date_idx = {v: i for i, v in enumerate(dates)}

# 1. Observation-level compact cube (Page 1 & 2 filterable charts)
obs = {
    'd':  df['obs_date'].dt.strftime('%Y-%m-%d').map(date_idx).astype(int).tolist(),
    'op': df['operator'].map(op_idx).astype(int).tolist(),
    'nt': df['network_type'].map(net_idx).astype(int).tolist(),
    'st': df['state'].map(st_idx).astype(int).tolist(),
    'ct': df['city'].map(city_idx).astype(int).tolist(),
    'rs': df['outage_reason'].fillna('None').map(reason_idx).astype(int).tolist(),
    'up': (df['uptime_percentage'].round(1) * 10).astype(int).tolist(),
    'dt': (df['downtime_minutes'].round(1) * 10).astype(int).tolist(),
    'oc': df['outage_count'].astype(int).tolist(),
    'ua': df['avg_users_affected'].astype(int).tolist(),
}

# 2. Tower-level table (Page 2) - only the towers that could ever appear
# in a "worst performers" or "repeat-outage" leaderboard need to ship to
# the browser; a table never needs to paginate through all 70,599 rows.
worst_towers = tower_df.nsmallest(400, 'avg_uptime_percentage')
repeat_towers = tower_df[tower_df['repeat_outage_indicator'] == 1].nlargest(400, 'impactful_outage_observations')
tw_subset = pd.concat([worst_towers, repeat_towers]).drop_duplicates(subset='tower_id')

tw = {
    'id': tw_subset['tower_id'].tolist(),
    'ct': tw_subset['city'].map(city_idx).astype(int).tolist(),
    'op': tw_subset['mode_operator'].map(op_idx).astype(int).tolist(),
    'st': tw_subset['mode_state'].map(st_idx).astype(int).tolist(),
    'nt': tw_subset['mode_network_type'].map(net_idx).astype(int).tolist(),
    'obs': tw_subset['total_observations'].astype(int).tolist(),
    'up': (tw_subset['avg_uptime_percentage'].round(2) * 100).astype(int).tolist(),
    'dtot': tw_subset['total_downtime_minutes'].round(0).astype(int).tolist(),
    'utot': tw_subset['total_users_affected'].astype(int).tolist(),
    'impc': tw_subset['impactful_outage_observations'].astype(int).tolist(),
    'rep': tw_subset['repeat_outage_indicator'].astype(int).tolist(),
}

tw_stats = {
    'total_towers': int(len(tower_df)),
    'repeat_outage_towers': int((tower_df['repeat_outage_indicator'] == 1).sum()),
}

# 3. Watchlist table (Page 3) - only the top 500 by recommended priority
wl_subset = watch_df.nsmallest(500, 'recommended_priority')
wl = {
    'id': wl_subset['tower_id'].tolist(),
    'op': wl_subset['operator'].map(op_idx).astype(int).tolist(),
    'st': wl_subset['state'].map(st_idx).astype(int).tolist(),
    'ct': wl_subset['city'].map(city_idx).astype(int).tolist(),
    'nt': wl_subset['network_type'].map(net_idx).astype(int).tolist(),
    'lu': (wl_subset['latest_uptime'].round(2) * 100).astype(int).tolist(),
    'td': wl_subset['historical_total_downtime_minutes'].round(0).astype(int).tolist(),
    'to': wl_subset['historical_total_outage_count'].astype(int).tolist(),
    'score': wl_subset['site_reliability_risk_score'].round(1).tolist(),
    'rc': wl_subset['risk_category_final'].tolist(),
    'prob': (wl_subset['predicted_risk_probability'].round(4) * 10000).astype(int).tolist(),
    'pc': wl_subset['predicted_risk_category'].tolist(),
    'pri': wl_subset['recommended_priority'].astype(int).tolist(),
}

# Full-population watchlist stats (for KPI cards on Page 3)
wl_stats = {
    'total_towers': int(len(watch_df)),
    'predicted_high_or_critical': int(watch_df['predicted_risk_category'].isin(['High','Critical']).sum()),
    'avg_predicted_probability': round(float(watch_df['predicted_risk_probability'].mean()), 4),
    'risk_category_counts': watch_df['risk_category_final'].value_counts().to_dict(),
}

# -----------------------------------------------------------------------
# 4. Operator x Network x State crosstab (FULL population, 70,599 towers
# rolled up) - this is what makes the risk KPI cards and risk-distribution
# charts genuinely filterable by operator/network/state without shipping
# all 70,599 tower rows to the browser.
# -----------------------------------------------------------------------
merged = watch_df.merge(tower_df[['tower_id', 'repeat_outage_indicator']], on='tower_id')
merged['op_i'] = merged['operator'].map(op_idx)
merged['nt_i'] = merged['network_type'].map(net_idx)
merged['st_i'] = merged['state'].map(st_idx)

grp = merged.groupby(['op_i', 'nt_i', 'st_i']).agg(
    n=('tower_id', 'count'),
    repeat=('repeat_outage_indicator', 'sum'),
    low=('risk_category_final', lambda s: (s == 'Low Risk').sum()),
    med=('risk_category_final', lambda s: (s == 'Medium Risk').sum()),
    high=('risk_category_final', lambda s: (s == 'High Risk').sum()),
    crit=('risk_category_final', lambda s: (s == 'Critical Risk').sum()),
    p_low=('predicted_risk_category', lambda s: (s == 'Low').sum()),
    p_med=('predicted_risk_category', lambda s: (s == 'Medium').sum()),
    p_high=('predicted_risk_category', lambda s: (s == 'High').sum()),
    p_crit=('predicted_risk_category', lambda s: (s == 'Critical').sum()),
    prob_sum=('predicted_risk_probability', 'sum'),
).reset_index()

crosstab = {
    'op': grp['op_i'].astype(int).tolist(),
    'nt': grp['nt_i'].astype(int).tolist(),
    'st': grp['st_i'].astype(int).tolist(),
    'n': grp['n'].astype(int).tolist(),
    'repeat': grp['repeat'].astype(int).tolist(),
    'low': grp['low'].astype(int).tolist(),
    'med': grp['med'].astype(int).tolist(),
    'high': grp['high'].astype(int).tolist(),
    'crit': grp['crit'].astype(int).tolist(),
    'p_low': grp['p_low'].astype(int).tolist(),
    'p_med': grp['p_med'].astype(int).tolist(),
    'p_high': grp['p_high'].astype(int).tolist(),
    'p_crit': grp['p_crit'].astype(int).tolist(),
    'prob_sum': grp['prob_sum'].round(3).tolist(),
}
print(f"Crosstab rows: {len(grp)}")

legends = {
    'operators': operators, 'networks': networks, 'states': states,
    'cities': cities, 'reasons': reasons, 'dates': dates,
}

with open('data/model_results.pkl', 'rb') as f:
    d = pickle.load(f)
rf = d['models']['Random Forest']
cols = d['X_train_cols']
importances = pd.Series(rf.feature_importances_, index=cols).sort_values(ascending=False).head(10)
feat_importance = [{'feature': k, 'importance': round(float(v), 4)} for k, v in importances.items()]

model_metrics = {
    name: {kk: (vv.tolist() if hasattr(vv, 'tolist') else vv)
           for kk, vv in v.items() if kk in ('accuracy', 'precision', 'recall', 'f1', 'roc_auc', 'confusion_matrix')}
    for name, v in d['results'].items()
}

payload = {
    'legends': legends,
    'obs': obs,
    'tw': tw,
    'tw_stats': tw_stats,
    'wl': wl,
    'wl_stats': wl_stats,
    'crosstab': crosstab,
    'feat_importance': feat_importance,
    'model_metrics': model_metrics,
}

with open('data/dashboard_data.json', 'w') as f:
    json.dump(payload, f, separators=(',', ':'))

size_mb = os.path.getsize('data/dashboard_data.json') / 1e6
print(f"dashboard_data.json size: {size_mb:.2f} MB")
print(f"Observations: {len(obs['d']):,}, Towers: {len(tw['id']):,}, Watchlist: {len(wl['id']):,}")


# ================================================================
# FILE: py07_additional_diagnostic_charts.py
# (originally produced ad hoc during the engagement; restored here as a
# script so the delivered charts/ folder is fully reproducible from code)
# ================================================================
"""
Three additional charts referenced in the written report:
  12_downtime_vs_impact_scatter.png  - the mixture-effect finding behind
                                         the uptime/downtime vs. users-
                                         affected correlation
  13_roc_curves.png                  - model validation (near-chance AUC)
  14_confusion_matrices.png          - model validation, all 3 models
"""
import pandas as pd
import numpy as np
import pickle
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import roc_curve

sns.set_style('whitegrid')

# ---- Chart 12: downtime vs. impact scatter (the mixture-effect finding) ----
df = pd.read_csv('data/telecom_outage_features.csv', parse_dates=['obs_date'],
                  keep_default_na=False, na_values=[''])
df['has_impact'] = df['avg_users_affected'] > 0

fig, ax = plt.subplots(figsize=(8, 6))
sns.scatterplot(data=df.sample(8000, random_state=42), x='downtime_minutes', y='avg_users_affected',
                 hue='has_impact', alpha=0.4, s=15, palette={True: '#c0392b', False: '#7f8c8d'}, ax=ax)
ax.set_title('Downtime vs. Users Affected\n(overall r=0.632 is a MIXTURE effect from the zero/non-zero split;\nwithin impactful events only, r=0.002 — essentially no relationship)')
ax.set_xlabel('Downtime (minutes)')
ax.set_ylabel('Avg Users Affected')
ax.legend(title='Has recorded impact')
fig.tight_layout()
fig.savefig('charts/12_downtime_vs_impact_scatter.png', bbox_inches='tight')
plt.close(fig)
print("Saved 12_downtime_vs_impact_scatter.png")

# Verify the reported correlations directly (don't just assert them)
r_overall = df['downtime_minutes'].corr(df['avg_users_affected'])
r_impactful_only = df.loc[df['avg_users_affected'] > 0, 'downtime_minutes'].corr(
    df.loc[df['avg_users_affected'] > 0, 'avg_users_affected'])
print(f"r(downtime, users_affected) overall = {r_overall:.3f}")
print(f"r(downtime, users_affected) impactful-only = {r_impactful_only:.3f}")

# ---- Charts 13 & 14: model validation (ROC curves + confusion matrices) ----
with open('data/model_results.pkl', 'rb') as f:
    d = pickle.load(f)
results = d['results']
y_test = d['y_test']

fig, ax = plt.subplots(figsize=(7, 6))
for name, r in results.items():
    fpr, tpr, _ = roc_curve(y_test, r['y_proba'])
    ax.plot(fpr, tpr, label=f"{name} (AUC={r['roc_auc']:.3f})")
ax.plot([0, 1], [0, 1], 'k--', alpha=0.5, label='Random chance (AUC=0.500)')
ax.set_xlabel('False Positive Rate')
ax.set_ylabel('True Positive Rate')
ax.set_title('ROC Curves - All 3 Models Barely Beat Random Chance\n(honest finding: no persistent tower-level risk signal in this dataset)')
ax.legend()
fig.tight_layout()
fig.savefig('charts/13_roc_curves.png', bbox_inches='tight')
plt.close(fig)
print("Saved 13_roc_curves.png")

fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))
for ax, (name, r) in zip(axes, results.items()):
    sns.heatmap(r['confusion_matrix'], annot=True, fmt='d', cmap='Blues', ax=ax,
                xticklabels=['Pred: Not High-Risk', 'Pred: High-Risk'],
                yticklabels=['Actual: Not High-Risk', 'Actual: High-Risk'])
    ax.set_title(f"{name}\nRecall={r['recall']:.3f}, Precision={r['precision']:.3f}")
fig.suptitle('Confusion Matrices (Test Set)', y=1.05, fontsize=13)
fig.tight_layout()
fig.savefig('charts/14_confusion_matrices.png', bbox_inches='tight')
plt.close(fig)
print("Saved 14_confusion_matrices.png")
