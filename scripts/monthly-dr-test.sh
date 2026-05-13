#!/bin/bash
# scripts/monthly-dr-test.sh

# Variables
BACKUP_NAME=$(velero backup get -o json | jq -r '.items[0].metadata.name')
TEST_NAMESPACE="ml-workloads-dr-test-$(date +%Y%m%d)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "Starting Disaster Recovery Test: $TIMESTAMP"
echo "Using backup: $BACKUP_NAME"

# Create test namespace
kubectl create namespace $TEST_NAMESPACE

# Restore to test namespace
velero restore create dr-test-$TIMESTAMP \
  --from-backup $BACKUP_NAME \
  --namespace-mappings ml-workloads:$TEST_NAMESPACE \
  --wait

# Verify restore
if [ $? -eq 0 ]; then
    echo "✓ Restore successful"
    
    # Verify pods are running
    kubectl wait --for=condition=ready pod -l workload-type=gpu-inference -n $TEST_NAMESPACE --timeout=5m
    
    if [ $? -eq 0 ]; then
        echo "✓ Pods are running"
        echo "✓ Disaster Recovery Test PASSED"
        
        # Clean up test namespace
        kubectl delete namespace $TEST_NAMESPACE
    else
        echo "✗ Pods failed to start"
        echo "✗ Disaster Recovery Test FAILED"
        exit 1
    fi
else
    echo "✗ Restore failed"
    echo "✗ Disaster Recovery Test FAILED"
    exit 1
fi
