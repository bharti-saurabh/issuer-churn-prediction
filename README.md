# Issuer Churn Prediction

**Client Segment:** Issuer
**Category:** Customer Profiling
**Owner:** Straive Strategic Analytics
**Year:** 2024

## Objective
Predict cardholder attrition 90 days in advance using transactional and behavioural signals, enabling the issuer to deploy targeted retention offers before the churn event.

## Methodology
1. Feature engineering from 24-month transactional history (spend velocity, category diversity, dormancy windows)
2. XGBoost binary classifier with SHAP-based explainability
3. Monthly batch scoring pipeline via SQL + Python
4. Output: churn probability score (0–1) per active cardholder

## Key Metrics
| Metric | Value |
|---|---|
| AUC-ROC | 0.87 |
| Precision@Top10% | 72% |
| Monthly Cardholders Scored | ~2.4M |
| Retention Lift vs. Control | +18% |

## Assets
- `src/churn_model.py` — Model training, evaluation, SHAP analysis
- `src/scoring_pipeline.py` — Monthly batch scoring
- `sql/cardholder_features.sql` — Feature extraction query
- `sql/churn_labels.sql` — Label generation (90-day outcome window)

## Requirements
```
xgboost>=1.7
scikit-learn>=1.3
shap>=0.43
pandas>=2.0
sqlalchemy>=2.0
```
