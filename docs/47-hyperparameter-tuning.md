# Hyperparameter Optimization (HPO)

**Component:** Model Tuning  
**Objective:** Automate the discovery of optimal learning configurations at scale  
**Architecture:** Ray Tune + Optuna Backend  

---

## 1. The Combinatorial Explosion of ML Tuning

Training a neural network requires configuring Hyperparameters before training begins (e.g., Learning Rate, Batch Size, Dropout Rate, Weight Decay). These parameters dictate whether a model converges to high accuracy or fails completely.

Manually guessing these parameters or executing grid searches sequentially on a single GPU is mathematically inefficient and wastes days of compute time.

---

## 2. Distributed HPO Architecture

To exploit the full capacity of the bare-metal GPU cluster, this architecture deploys **Ray Tune** backed by **Optuna**.

- **Optuna:** Provides state-of-the-art search algorithms (e.g., Tree-structured Parzen Estimator, TPE) to intelligently guess the next best set of parameters based on the results of previous trials.
- **Ray Tune:** Orchestrates the execution of these trials across the physical cluster, dynamically spinning up worker Pods and scheduling them onto available Time-Sliced GPUs.

---

## 3. Implementation

### 3.1 Python Tuning Script

The script defines the search space and delegates the trial execution to the Ray cluster (`21-ray-distributed-ml.md`).

```python
# tune.py
import ray
from ray import tune
from ray.tune.search.optuna import OptunaSearch
import torch

def objective(config):
    # Retrieve hyperparameters from the Optuna trial
    lr = config["lr"]
    batch_size = config["batch_size"]
    
    # Initialize Model and Optimizer
    model = get_model()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    
    # Train Loop
    for epoch in range(10):
        accuracy = train_epoch(model, optimizer, batch_size)
        # Report the metric back to Ray Tune
        tune.report(accuracy=accuracy)

if __name__ == "__main__":
    ray.init(address="ray://kuberay-head:10001")
    
    # Define the search space
    search_space = {
        "lr": tune.loguniform(1e-5, 1e-1),
        "batch_size": tune.choice([16, 32, 64, 128])
    }
    
    # Initialize the Optuna Search Algorithm
    algo = OptunaSearch()
    
    # Execute the distributed trials
    tuner = tune.Tuner(
        objective,
        tune_config=tune.TuneConfig(
            metric="accuracy",
            mode="max",
            search_alg=algo,
            num_samples=50  # Run 50 different configurations
        ),
        param_space=search_space,
        run_config=air.RunConfig(name="vision_hpo_run")
    )
    results = tuner.fit()
    print(f"Best hyperparameters found: {results.get_best_result().config}")
```

### 3.2 Advanced Capabilities: ASHA Scheduling

To maximize GPU utilization, Ray Tune employs the **Asynchronous Successive Halving Algorithm (ASHA)**. 
If a trial (e.g., Trial 12) is performing terribly after 2 epochs, ASHA aggressively terminates the trial early, freeing the GPU Time-Slice for a new trial rather than wasting compute resources finishing a doomed configuration.

---

## Next Steps

Proceed to `48-canary-deployments-ab-testing.md` to deploy the optimized model safely.
