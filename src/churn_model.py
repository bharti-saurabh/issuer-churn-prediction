"""
Issuer Churn Prediction Model
Straive Strategic Analytics — Customer Profiling Practice
"""

import pandas as pd
import numpy as np
from xgboost import XGBClassifier
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import roc_auc_score, average_precision_score
from sklearn.preprocessing import LabelEncoder
import shap
import joblib
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

FEATURE_COLS = [
    # Spend velocity
    "spend_30d", "spend_90d", "spend_180d", "spend_yoy_delta",
    # Transaction behaviour
    "txn_count_30d", "txn_count_90d", "avg_txn_value_90d",
    "unique_merchants_90d", "unique_categories_90d",
    # Dormancy signals
    "days_since_last_txn", "days_since_last_international_txn",
    "dormancy_flag_60d", "dormancy_flag_90d",
    # Product utilisation
    "revolve_rate_90d", "cash_advance_count_90d",
    "autopay_active", "reward_redemption_count_90d",
    # Demographic proxies
    "account_tenure_months", "credit_limit_utilisation",
    "credit_limit_increase_count_24m",
]
TARGET = "churned_90d"


def load_data(path: str) -> pd.DataFrame:
    df = pd.read_parquet(path)
    log.info(f"Loaded {len(df):,} records — churn rate: {df[TARGET].mean():.2%}")
    return df


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["spend_trend"] = df["spend_90d"] / (df["spend_180d"] + 1)
    df["txn_intensity"] = df["txn_count_30d"] / (df["days_since_last_txn"] + 1)
    df["breadth_score"] = df["unique_categories_90d"] * df["unique_merchants_90d"]
    df["reward_engagement"] = (df["reward_redemption_count_90d"] > 0).astype(int)
    return df


def train(data_path: str, model_out: str = "churn_model.pkl"):
    df = load_data(data_path)
    df = engineer_features(df)

    X = df[FEATURE_COLS + ["spend_trend", "txn_intensity", "breadth_score", "reward_engagement"]]
    y = df[TARGET]

    model = XGBClassifier(
        n_estimators=500,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        scale_pos_weight=(y == 0).sum() / (y == 1).sum(),
        eval_metric="auc",
        early_stopping_rounds=30,
        random_state=42,
        n_jobs=-1,
    )

    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    oof_preds = np.zeros(len(y))

    for fold, (train_idx, val_idx) in enumerate(cv.split(X, y)):
        X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_val = y.iloc[train_idx], y.iloc[val_idx]
        model.fit(X_tr, y_tr, eval_set=[(X_val, y_val)], verbose=False)
        oof_preds[val_idx] = model.predict_proba(X_val)[:, 1]
        log.info(f"Fold {fold+1} AUC: {roc_auc_score(y_val, oof_preds[val_idx]):.4f}")

    log.info(f"OOF AUC: {roc_auc_score(y, oof_preds):.4f}")
    log.info(f"OOF AP:  {average_precision_score(y, oof_preds):.4f}")

    # Retrain on full data
    model.fit(X, y, verbose=False)
    joblib.dump(model, model_out)
    log.info(f"Model saved → {model_out}")

    # SHAP explainability
    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(X.sample(min(5000, len(X)), random_state=42))
    mean_abs_shap = pd.Series(
        np.abs(shap_values).mean(axis=0), index=X.columns
    ).sort_values(ascending=False)
    log.info("Top 10 features by mean |SHAP|:")
    log.info(mean_abs_shap.head(10).to_string())

    return model


def score_batch(model_path: str, data_path: str, output_path: str):
    model = joblib.load(model_path)
    df = load_data(data_path)
    df = engineer_features(df)
    X = df[model.feature_names_in_]
    df["churn_probability"] = model.predict_proba(X)[:, 1]
    df["churn_decile"] = pd.qcut(df["churn_probability"], 10, labels=False) + 1
    df[["account_id", "churn_probability", "churn_decile"]].to_parquet(output_path, index=False)
    log.info(f"Scored {len(df):,} accounts → {output_path}")


if __name__ == "__main__":
    train("data/training_set.parquet")
