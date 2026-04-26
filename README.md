# AWS Auto Scaling Group with ELB & CloudWatch Alarms Lab

This lab demonstrates a core architectural pattern for the **AWS SysOps Administrator Associate**: building a highly available and dynamically scalable web application tier.

## Architecture Overview

The system implements a self-healing and auto-scaling compute layer:

1.  **Multi-AZ Network:** A custom VPC with two public subnets in different Availability Zones (`us-east-1a` and `us-east-1b`).
2.  **Traffic Distribution:** An Application Load Balancer (ALB) routes incoming HTTP traffic across multiple EC2 instances.
3.  **Self-Healing:** An Auto Scaling Group (ASG) maintains a desired number of instances and replaces any that fail health checks.
4.  **Dynamic Scaling:** CloudWatch Alarms monitor average CPU utilization and trigger Scaling Policies to add or remove instances based on demand.

## Key Components

-   **Launch Template:** Blueprint for EC2 instances, including a Python-based web server script.
-   **Application Load Balancer (ALB):** Internet-facing balancer with Target Group and Health Checks.
-   **Auto Scaling Group (ASG):** Configured with a capacity range of 1 to 4 instances.
-   **CloudWatch Alarms:**
    -   `cpu-high-alarm`: Triggers when CPU > 70% (Scales Up).
    -   `cpu-low-alarm`: Triggers when CPU < 30% (Scales Down).

## Prerequisites

-   [Terraform](https://www.terraform.io/downloads.html)
-   [LocalStack](https://localstack.cloud/)
-   [AWS CLI / awslocal](https://github.com/localstack/awscli-local)

## Deployment

1.  **Initialize and Apply:**
    ```bash
    terraform init
    terraform apply -auto-approve
    ```

## Verification & Testing

To observe the architecture in action:

1.  **Access the Load Balancer:**
    ```bash
    curl $(terraform output -raw alb_dns_name)
    ```
    Repeating this should show traffic alternating between different instance hostnames.

2.  **Verify Auto Scaling Group:**
    ```bash
    awslocal autoscaling describe-auto-scaling-groups --auto-scaling-group-name asg-lab-group
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name asg-lab-group
    ```

3.  **Simulate Load (Conceptual):**
    In a real environment, increasing CPU load on the instances would trigger the `cpu-high-alarm`, causing the ASG to scale out by adding more instances.

## Cleanup

To tear down the infrastructure:
```bash
terraform destroy -auto-approve
```

---

💡 **Pro Tip: Using `aws` instead of `awslocal`**

If you prefer using the standard `aws` CLI without the `awslocal` wrapper or repeating the `--endpoint-url` flag, you can configure a dedicated profile in your AWS config files.

### 1. Configure your Profile
Add the following to your `~/.aws/config` file:
```ini
[profile localstack]
region = us-east-1
output = json
# This line redirects all commands for this profile to LocalStack
endpoint_url = http://localhost:4566
```

Add matching dummy credentials to your `~/.aws/credentials` file:
```ini
[localstack]
aws_access_key_id = test
aws_secret_access_key = test
```

### 2. Use it in your Terminal
You can now run commands in two ways:

**Option A: Pass the profile flag**
```bash
aws iam create-user --user-name DevUser --profile localstack
```

**Option B: Set an environment variable (Recommended)**
Set your profile once in your session, and all subsequent `aws` commands will automatically target LocalStack:
```bash
export AWS_PROFILE=localstack
aws iam create-user --user-name DevUser
```

### Why this works
- **Precedence**: The AWS CLI (v2) supports a global `endpoint_url` setting within a profile. When this is set, the CLI automatically redirects all API calls for that profile to your local container instead of the real AWS cloud.
- **Convenience**: This allows you to use the standard documentation commands exactly as written, which is helpful if you are copy-pasting examples from AWS labs or tutorials.
