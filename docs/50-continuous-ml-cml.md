# Continuous Machine Learning (CML)

**Component:** CI/CD Integration  
**Objective:** Embed model performance metrics directly into the Code Review process  
**Architecture:** Iterative CML + GitHub Actions  

---

## 1. The Code Review Disconnect

In standard software engineering, a Pull Request (PR) review focuses on logic, syntax, and unit test results. However, when a Data Scientist modifies a PyTorch training script or alters hyperparameters, reviewing the code itself is insufficient. The reviewer must know how those code changes impacted the model's ultimate accuracy and loss.

Without automation, developers must manually cross-reference MLflow (`18-mlflow-registry.md`) dashboards during every PR review, leading to friction and oversight.

---

## 2. CML Architecture

**Continuous Machine Learning (CML)** bridges this gap. It acts as an automated CI/CD bot that executes the ML training pipeline, generates visual plots (e.g., Confusion Matrices, Loss Curves), and posts them as a markdown comment directly on the GitHub Pull Request.

This keeps the context of the model's mathematical performance natively within the Git workflow.

---

## 3. Implementation (GitHub Actions)

### 3.1 The Training Script Output

Ensure the PyTorch training script outputs standard markdown or text files containing the final metrics.

```python
# train.py
import matplotlib.pyplot as plt

def generate_report(accuracy, loss_history):
    # Write metrics to a text file
    with open("metrics.txt", "w") as f:
        f.write(f"Validation Accuracy: {accuracy * 100:.2f}%\n")
    
    # Generate and save a plot
    plt.plot(loss_history)
    plt.title("Training Loss")
    plt.savefig("loss_plot.png")

# ... training loop ...
```

### 3.2 CML GitHub Action Workflow

Define a `.github/workflows/cml.yml` pipeline that triggers on Pull Requests. The workflow provisions a GPU runner, trains the model, and utilizes the `cml` CLI to comment the results.

```yaml
name: Model Training CI
on: [pull_request]
jobs:
  train-and-report:
    runs-on: [self-hosted, gpu]  # Execute on the bare-metal k3s runner
    steps:
      - uses: actions/checkout@v3
      - uses: iterative/setup-cml@v1
      
      - name: Train model
        run: |
          pip install -r requirements.txt
          python train.py
          
      - name: Generate PR Comment
        env:
          REPO_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # Create a markdown report
          echo "## Model Performance Report" > report.md
          cat metrics.txt >> report.md
          
          echo "### Loss Curve" >> report.md
          # Embed the plot directly into the markdown
          cml publish loss_plot.png --md >> report.md
          
          # Post the comment to the active Pull Request
          cml send-comment report.md
```

**Result:** Every time a PR is opened modifying the ML pipeline, a bot posts a comprehensive statistical report, allowing Senior Engineers to merge or reject the PR based on empirical mathematical evidence rather than code aesthetics alone.

---

**End of Advanced Infrastructure Documentation Series.**
