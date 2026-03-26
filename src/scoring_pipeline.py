"""
Monthly Batch Scoring Pipeline — Issuer Churn
Straive Strategic Analytics
"""

import argparse
import logging
from datetime import date
from pathlib import Path
import pandas as pd
import sqlalchemy as sa
import joblib

log = logging.getLogger(__name__)


def extract_features(engine: sa.Engine, score_date: date) -> pd.DataFrame:
    query = Path("sql/cardholder_features.sql").read_text()
    df = pd.read_sql(query, engine, params={"score_date": score_date})
    log.info(f"Extracted {len(df):,} accounts for {score_date}")
    return df


def load_model(model_path: str):
    return joblib.load(model_path)


def run(db_url: str, model_path: str, output_table: str, score_date: date):
    engine = sa.create_engine(db_url)
    model = load_model(model_path)

    df = extract_features(engine, score_date)
    df["churn_probability"] = model.predict_proba(df[model.feature_names_in_])[:, 1]
    df["churn_decile"] = pd.qcut(df["churn_probability"], 10, labels=False) + 1
    df["score_date"] = score_date

    df[["account_id", "score_date", "churn_probability", "churn_decile"]].to_sql(
        output_table, engine, if_exists="append", index=False, method="multi"
    )
    log.info(f"Written {len(df):,} scores to {output_table}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--model", default="churn_model.pkl")
    parser.add_argument("--output-table", default="stg_churn_scores")
    parser.add_argument("--score-date", default=str(date.today()))
    args = parser.parse_args()
    run(args.db_url, args.model, args.output_table, date.fromisoformat(args.score_date))
